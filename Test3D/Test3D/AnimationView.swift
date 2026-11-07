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

    private var currentModelRoot: Entity?

    // MARK: - State

    private var persistentScale: Float?
    private var hasSetUpCamera = false
    private var transitionToken = UUID()

    private var currentSceneModel: SceneModel?
    private var currentScaledCenter = SIMD3<Float>(repeating: 0)
    private var currentScaledRadius: Float = 0
    private var cameraAzimuthOffset: Float = 0

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

        addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: topAnchor),
            arView.leadingAnchor.constraint(equalTo: leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
        cameraAzimuthOffset = 0
    }

    // MARK: - Preload (бандл)

    func preload(scenes: [SceneModel], completion: (() -> Void)? = nil) {
        let names = Set(scenes.map(\.name))
        SceneCache.shared.preload(names: names, completion: completion)
    }

    // MARK: - Play external (из папки на телефоне)

    /// Загружает `.usdz` / `.reality` из внешнего URL и сразу запускает.
    /// Внутри копирует файл в песочницу, чтобы security-scoped доступ не истёк.
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
                let scene = SceneModel(externalURL: url, name: name, radiusOrbitMul: 1.5, azimuth: .pi / 8, elevation: .pi / 6, scaledCenterMulX: 0, scaledCenterMulY: 0.1, scaledCenterMulZ: 0)
                self.play(scene: scene, loop: loop) {
                    completion?(.success(()))
                }
            case .failure(let error):
                print("❌ Ошибка загрузки внешнего файла: \(error)")
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Play (кэш или бандл)

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

        currentModelRoot?.removeFromParent()
        modelContainer.addChild(model)
        currentModelRoot = model

        model.isEnabled = true
        playAllAnimations(in: model, loop: loop)

        if !hasSetUpCamera {
            hasSetUpCamera = true
            updateCameraPosition()
        } else {
            updateCameraPosition()
        }

        if let completion = completion {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.transitionToken == token else { return }
                completion()
            }
        }
    }

    /// Рекурсивно запускает все анимации.
    private func playAllAnimations(in entity: Entity, loop: Bool) {
        for animation in entity.availableAnimations {
            let toPlay = loop ? animation.repeat(duration: .infinity) : animation
            entity.playAnimation(toPlay)
        }
        for child in entity.children {
            playAllAnimations(in: child, loop: loop)
        }
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

    private func updateCameraPosition() {
        guard let scene = currentSceneModel else { return }

        let effectiveAzimuth = scene.azimuth + cameraAzimuthOffset

        let lookAtTarget = SIMD3<Float>(
            currentScaledCenter.x + currentScaledRadius * scene.scaledCenterMulX,
            currentScaledCenter.y + currentScaledRadius * scene.scaledCenterMulY,
            currentScaledCenter.z + currentScaledRadius * scene.scaledCenterMulZ
        )
        let radiusOrbit = currentScaledRadius * scene.radiusOrbitMul
        let elevation = scene.elevation

        pivotEntity.position = lookAtTarget
        pivotEntity.orientation = simd_quatf(angle: effectiveAzimuth, axis: [0, 1, 0])

        cameraEntity.position = SIMD3<Float>(
            0,
            radiusOrbit * sin(elevation),
            radiusOrbit * cos(elevation)
        )

        cameraEntity.orientation = simd_quatf(angle: -elevation, axis: [1, 0, 0])
    }
}
