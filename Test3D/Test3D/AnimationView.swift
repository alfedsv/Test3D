//
//  AnimationView.swift
//  Test3D
//
//  Created by  Alexander Fedoseev on 07.11.2026.
//


import UIKit
import RealityKit
import simd

final class AnimationView: UIView {

    // MARK: - Private UI

    private let arView = ARView(
        frame: .zero,
        cameraMode: .nonAR,
        automaticallyConfigureSession: false
    )

    // MARK: - Scene graph

    private let sceneAnchor = AnchorEntity()
    private let pivotEntity = Entity()
    private let cameraEntity = Entity()
    private let modelContainer = Entity()

    /// Пол — тонкий бокс, прямоугольник. Стоит на Y = нижняя точка модели.
    private let floorEntity = ModelEntity()

    /// Направленный свет («солнце»). Позиция не важна — работает только ориентация.
    private let keyLight: DirectionalLight = {
        let light = DirectionalLight()
        light.light.color = .white
        light.light.intensity = 5000
        light.shadow = DirectionalLightComponent.Shadow()
        light.shadow?.maximumDistance = 50
        // Наклоняем свет сверху-сбоку, чтобы грани модели были видны объёмно.
        light.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
            * simd_quatf(angle: .pi / 6, axis: [0, 1, 0])
        return light
    }()

    private var currentModelRoot: Entity?

    // MARK: - State

    private var persistentScale: Float?
    private var hasSetUpCamera = false
    private var transitionToken = UUID()

    private var currentSceneModel: SceneModel?
    private var currentScaledCenter = SIMD3<Float>(repeating: 0)
    private var currentScaledRadius: Float = 0
    /// Y-координата нижней точки модели в мировых координатах — «пол».
    private var currentScaledFloorY: Float = 0

    private var cameraAzimuthOffset: Float = 0
    /// Абсолютный elevation камеры (а не offset). `nil` — берём `scene.elevation`.
    private var cameraElevationAbsolute: Float?

    /// Реальный доступный диапазон elevation с учётом пола.
    private(set) var elevationRange: ClosedRange<Float> = (-.pi / 2)...(.pi / 2)
    /// Текущий elevation (для инициализации слайдера).
    private(set) var currentElevation: Float = 0

    /// Вызывается каждый раз, когда меняется диапазон (после загрузки модели).
    var onElevationRangeChanged: ((ClosedRange<Float>, Float) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        arView.backgroundColor = .clear
        arView.environment.background = .color(.clear)
        arView.renderOptions.insert(.disableGroundingShadows)

        arView.scene.addAnchor(sceneAnchor)

        pivotEntity.position = .zero
        sceneAnchor.addChild(pivotEntity)

        cameraEntity.components.set(PerspectiveCameraComponent())
        pivotEntity.addChild(cameraEntity)

        sceneAnchor.addChild(modelContainer)

        setupFloor()

        sceneAnchor.addChild(keyLight)

        addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: topAnchor),
            arView.leadingAnchor.constraint(equalTo: leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupFloor() {
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(1, 0.02, 1))
        // Непрозрачный нейтральный серый — при ярком свете остаётся отличимым от белого фона.
        let material = SimpleMaterial(
            color: UIColor(white: 0.55, alpha: 1.0),
            roughness: 0.9,
            isMetallic: false
        )
        floorEntity.model = ModelComponent(mesh: mesh, materials: [material])
        floorEntity.isEnabled = false
        sceneAnchor.addChild(floorEntity)
    }

    // MARK: - Reset

    func reset() {
        transitionToken = UUID()
        currentModelRoot?.removeFromParent()
        currentModelRoot = nil
        persistentScale = nil
        hasSetUpCamera = false
        currentSceneModel = nil
        currentScaledCenter = .zero
        currentScaledRadius = 0
        currentScaledFloorY = 0
        cameraAzimuthOffset = 0
        cameraElevationAbsolute = nil
        floorEntity.isEnabled = false
    }

    // MARK: - Preload

    func preload(scenes: [SceneModel], completion: (() -> Void)? = nil) {
        let names = Set(scenes.map(\.name))
        SceneCache.shared.preload(names: names, completion: completion)
    }

    // MARK: - Play

    func play(scene exerciseScene: SceneModel, loop: Bool = true, completion: (() -> Void)? = nil) {
        let token = UUID()
        transitionToken = token

        guard let cached = SceneCache.shared.scene(named: exerciseScene.name) else {
            print("Сцена \(exerciseScene.name) отсутствует в кеше")
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.transitionToken == token else { return }
                completion?()
            }
            return
        }

        let model = cached.clone(recursive: true)

        if persistentScale == nil {
            let bounds = model.visualBounds(relativeTo: nil)
            let height = bounds.max.y - bounds.min.y
            let desiredHeight: Float = 2.0
            persistentScale = height > 0 ? desiredHeight / height : 1.0
        }
        let scale = persistentScale!
        model.scale = SIMD3<Float>(repeating: scale)

        model.isEnabled = false

        let bounds = model.visualBounds(relativeTo: nil)
        let center = (bounds.min + bounds.max) / 2
        let size = bounds.max - bounds.min
        let radius = simd_length(size) / 2

        currentSceneModel = exerciseScene
        currentScaledCenter = center
        currentScaledRadius = radius
        currentScaledFloorY = bounds.min.y

        // ── Пол ────────────────────────────────────────────────
        let floorExtent = max(size.x, size.z) * 2.0
        let floorThickness: Float = 0.02
        floorEntity.position = SIMD3<Float>(
            center.x,
            bounds.min.y - floorThickness / 2,
            center.z
        )
        floorEntity.scale = SIMD3<Float>(floorExtent, 1, floorExtent)
        floorEntity.isEnabled = true

        // ── Модель ─────────────────────────────────────────────
        currentModelRoot?.removeFromParent()
        modelContainer.addChild(model)
        currentModelRoot = model

        model.isEnabled = true
        playAllAnimations(in: model, loop: loop)

        // ── Камера ─────────────────────────────────────────────
        if !hasSetUpCamera {
            hasSetUpCamera = true
        }
        updateElevationRange(for: exerciseScene)
        updateCameraPosition()

        if let completion = completion {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.transitionToken == token else { return }
                completion()
            }
        }
    }

    /// Загрузка из внешнего URL (папка на телефоне).
    func playExternal(
        from url: URL,
        loop: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let token = UUID()
        transitionToken = token

        SceneCache.shared.loadEntity(from: url) { [weak self] result in
            guard let self = self, self.transitionToken == token else { return }

            switch result {
            case .success:
                let name = url.deletingPathExtension().lastPathComponent
                let scene = SceneModel(externalURL: url, name: name, radiusOrbitMul: 2.0, azimuth: .pi / 8, elevation: 0, scaledCenterMulX: 0, scaledCenterMulY: 0.1, scaledCenterMulZ: 0)
                self.play(scene: scene, loop: loop) {
                    completion?(.success(()))
                }
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    private func playAllAnimations(in entity: Entity, loop: Bool) {
        for animation in entity.availableAnimations {
            let toPlay = loop ? animation.repeat(duration: .infinity) : animation
            entity.playAnimation(toPlay)
        }
        for child in entity.children {
            playAllAnimations(in: child, loop: loop)
        }
    }

    // MARK: - Lighting

    /// Устанавливает интенсивность направленного света (в люксах).
    /// 0 — свет выключен (остаётся только фоновое IBL).
    func setKeyLightIntensity(_ intensity: Float) {
        keyLight.light.intensity = intensity
    }

    var keyLightIntensity: Float {
        keyLight.light.intensity
    }

    // MARK: - Elevation range

    private func updateElevationRange(for scene: SceneModel) {
        let lookAtTarget = SIMD3<Float>(
            currentScaledCenter.x + currentScaledRadius * scene.scaledCenterMulX,
            currentScaledCenter.y + currentScaledRadius * scene.scaledCenterMulY,
            currentScaledCenter.z + currentScaledRadius * scene.scaledCenterMulZ
        )
        let radiusOrbit = currentScaledRadius * scene.radiusOrbitMul
        let safeRadiusOrbit = max(radiusOrbit, 0.0001)

        let sinMin = (currentScaledFloorY - lookAtTarget.y) / safeRadiusOrbit
        let minElevation: Float
        if sinMin <= -1 {
            minElevation = -.pi / 2
        } else if sinMin >= 1 {
            minElevation = .pi / 2
        } else {
            minElevation = asin(sinMin)
        }

        let newRange = minElevation...(.pi / 2)
        elevationRange = newRange

        let rawElevation = cameraElevationAbsolute ?? scene.elevation
        let clamped = min(newRange.upperBound, max(newRange.lowerBound, rawElevation))
        currentElevation = clamped

        onElevationRangeChanged?(newRange, clamped)
    }

    // MARK: - Camera orbit

    func setCameraAzimuthOffset(_ azimuthOffset: Float) {
        cameraAzimuthOffset = azimuthOffset
        updateCameraPosition()
    }

    func resetCameraAzimuthOffset() {
        cameraAzimuthOffset = 0
        updateCameraPosition()
    }

    func setCameraElevation(_ elevation: Float) {
        let clamped = min(elevationRange.upperBound, max(elevationRange.lowerBound, elevation))
        currentElevation = clamped
        cameraElevationAbsolute = clamped
        updateCameraPosition()
    }

    private func updateCameraPosition() {
        guard let scene = currentSceneModel else { return }

        let effectiveAzimuth = scene.azimuth + cameraAzimuthOffset
        let effectiveElevation = min(
            elevationRange.upperBound,
            max(elevationRange.lowerBound, currentElevation)
        )

        let lookAtTarget = SIMD3<Float>(
            currentScaledCenter.x + currentScaledRadius * scene.scaledCenterMulX,
            currentScaledCenter.y + currentScaledRadius * scene.scaledCenterMulY,
            currentScaledCenter.z + currentScaledRadius * scene.scaledCenterMulZ
        )
        let radiusOrbit = currentScaledRadius * scene.radiusOrbitMul

        pivotEntity.position = lookAtTarget
        pivotEntity.orientation = simd_quatf(angle: effectiveAzimuth, axis: [0, 1, 0])

        cameraEntity.position = SIMD3<Float>(
            0,
            radiusOrbit * sin(effectiveElevation),
            radiusOrbit * cos(effectiveElevation)
        )
        cameraEntity.orientation = simd_quatf(angle: -effectiveElevation, axis: [1, 0, 0])
    }
}
