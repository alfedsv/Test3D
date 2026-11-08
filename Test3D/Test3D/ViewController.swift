//
//  ViewController.swift
//  Test3D
//
//  Created by  Alexander Fedoseev on 07.11.2026.
//


import UIKit
import UniformTypeIdentifiers

final class ViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: ViewModelProtocol = ViewModel()

    // MARK: - UI Elements

    private let azimuthLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .darkGray
        label.text = "Азимут: 0.00π"
        return label
    }()

    private let elevationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .darkGray
        label.text = "Наклон: 0.00π"
        return label
    }()

    private let animationView = AnimationView()

    private let azimuthSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -Float.pi
        slider.maximumValue = Float.pi
        slider.value = 0
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .systemBlue
        return slider
    }()

    private let elevationSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -Float.pi / 2
        slider.maximumValue = Float.pi / 2
        slider.value = 0
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .systemBlue
        return slider
    }()

    private let lightTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .darkGray
        return label
    }()

    private let lightSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 10000
        slider.value = 5000
        slider.minimumTrackTintColor = .systemGray4
        slider.maximumTrackTintColor = .systemYellow
        return slider
    }()

    private let loadButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(
            UIImage(systemName: "square.and.arrow.up", withConfiguration: config),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = .systemOrange
        button.layer.cornerRadius = 12
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        bindAnimationView()
        startPlaying()

        // Пока идёт предзагрузка — показываем целевое значение азимута из модели,
        // чтобы не было скачка с 0.00π на актуальное после подгрузки.
        updateAzimuthLabel(viewModel.model.azimuth)
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.onError = { [weak self] message in
            self?.showError(message)
        }
        viewModel.onUpload = { [weak self] url in
            self?.handlePickedFile(url)
        }
    }

    private func bindAnimationView() {
        animationView.onError = { [weak self] message in
            self?.viewModel.onError?(message)
        }

        animationView.onElevationRangeChanged = { [weak self] range, elevation in
            guard let self = self else { return }
            self.elevationSlider.minimumValue = range.lowerBound
            self.elevationSlider.maximumValue = range.upperBound
            self.elevationSlider.value = elevation
            self.updateElevationLabel(elevation)
        }
    }

    // MARK: - Start

    private func startPlaying() {
        let scene = viewModel.model
        guard !scene.name.isEmpty else {
            viewModel.onError?("Имя сцены не задано. Заполните `viewModel.model.name`.")
            return
        }
        animationView.preload(scenes: [scene]) { [weak self] in
            guard let self = self else { return }
            self.animationView.play(scene: scene, loop: true) { [weak self] in
                self?.syncAzimuthLabel()
            }
        }
    }

    // MARK: - File picking

    @objc private func loadButtonTapped() {
        let contentTypes: [UTType] = [
            .usdz,
            UTType(filenameExtension: "reality") ?? .data
        ].compactMap { $0 }

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func handlePickedFile(_ url: URL) {
        animationView.playExternal(from: url, loop: true) { [weak self] in
            self?.syncAzimuthLabel()
        }
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = .white

        azimuthSlider.addTarget(self, action: #selector(cameraSliderChanged(_:)), for: .valueChanged)

        elevationSlider.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        elevationSlider.addTarget(self, action: #selector(elevationSliderChanged(_:)), for: .valueChanged)

        lightSlider.addTarget(self, action: #selector(lightSliderChanged(_:)), for: .valueChanged)
        updateLightTitle(with: lightSlider.value)

        loadButton.addTarget(self, action: #selector(loadButtonTapped), for: .touchUpInside)

        view.addSubview(azimuthLabel)
        view.addSubview(elevationLabel)
        view.addSubview(animationView)
        view.addSubview(azimuthSlider)
        view.addSubview(elevationSlider)
        view.addSubview(lightTitleLabel)
        view.addSubview(lightSlider)
        view.addSubview(loadButton)

        setupConstraints()
    }

    // MARK: - Formatting

    private func piString(_ radians: Float) -> String {
        let coefficient = radians / .pi
        return String(format: "%.2fπ", coefficient)
    }

    private func updateAzimuthLabel(_ value: Float) {
        azimuthLabel.text = "Азимут: \(piString(value))"
    }

    private func updateElevationLabel(_ value: Float) {
        elevationLabel.text = "Наклон: \(piString(value))"
    }

    private func updateLightTitle(with intensity: Float) {
        let rounded = Int(intensity.rounded())
        lightTitleLabel.text = "Освещение: \(rounded) лк"
    }

    /// Синхронизирует тайтл азимута с фактическим состоянием камеры.
    /// Вызывается после загрузки сцены (бандловой или внешней).
    private func syncAzimuthLabel() {
        updateAzimuthLabel(animationView.effectiveAzimuth)
    }

    // MARK: - Error presentation

    private func showError(_ message: String) {
        guard presentedViewController == nil else {
            print("⚠️ Ошибка (алерт уже показан): \(message)")
            return
        }

        let alert = UIAlertController(
            title: "Ошибка",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func cameraSliderChanged(_ sender: UISlider) {
        animationView.setCameraAzimuthOffset(sender.value)
        // Показываем фактический угол камеры, а не offset слайдера.
        updateAzimuthLabel(animationView.effectiveAzimuth)
    }

    @objc private func elevationSliderChanged(_ sender: UISlider) {
        animationView.setCameraElevation(sender.value)
        updateElevationLabel(sender.value)
    }

    @objc private func lightSliderChanged(_ sender: UISlider) {
        animationView.setKeyLightIntensity(sender.value)
        updateLightTitle(with: sender.value)
    }
}

// MARK: - UIDocumentPickerDelegate

extension ViewController: UIDocumentPickerDelegate {

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else { return }
        viewModel.upload(from: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Отмена — не ошибка.
    }
}

// MARK: - Layout

private extension ViewController {
    func setupConstraints() {
        [
            azimuthLabel,
            elevationLabel,
            animationView,
            azimuthSlider,
            elevationSlider,
            lightTitleLabel,
            lightSlider,
            loadButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            azimuthLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            azimuthLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            azimuthLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            elevationLabel.topAnchor.constraint(equalTo: azimuthLabel.bottomAnchor, constant: 2),
            elevationLabel.leadingAnchor.constraint(equalTo: azimuthLabel.leadingAnchor),
            elevationLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            animationView.topAnchor.constraint(equalTo: elevationLabel.bottomAnchor, constant: 8),
            animationView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            animationView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
            animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor),

            azimuthSlider.topAnchor.constraint(equalTo: animationView.bottomAnchor, constant: 5),
            azimuthSlider.centerXAnchor.constraint(equalTo: animationView.centerXAnchor),
            azimuthSlider.widthAnchor.constraint(equalTo: animationView.widthAnchor),

            elevationSlider.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            elevationSlider.centerYAnchor.constraint(equalTo: animationView.centerYAnchor),
            elevationSlider.widthAnchor.constraint(equalToConstant: 200),
            elevationSlider.heightAnchor.constraint(equalToConstant: 30),

            lightTitleLabel.topAnchor.constraint(equalTo: azimuthSlider.bottomAnchor, constant: 12),
            lightTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            lightTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            lightSlider.topAnchor.constraint(equalTo: lightTitleLabel.bottomAnchor, constant: 4),
            lightSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            lightSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            loadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            loadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            loadButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
