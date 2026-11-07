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

    /// Тайтл с текущим азимутом камеры в единицах π.
    private let azimuthLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .darkGray
        label.text = "Азимут: 0.00π"
        return label
    }()

    /// Тайтл с текущим наклоном камеры в единицах π.
    private let elevationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .darkGray
        label.text = "Наклон: 0.00π"
        return label
    }()

    private let animationView = AnimationView()
    private let cameraSlider = UISlider()

    /// Вертикальный слайдер elevation.
    private let elevationSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = -Float.pi / 2
        slider.maximumValue = Float.pi / 2
        slider.value = 0
        slider.minimumTrackTintColor = .systemRed
        slider.maximumTrackTintColor = .systemGreen
        return slider
    }()

    /// Тайтл над слайдером освещения.
    private let lightTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .darkGray
        return label
    }()

    /// Слайдер интенсивности направленного света (в люксах).
    private let lightSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 10000
        slider.value = 5000
        slider.minimumTrackTintColor = .systemYellow
        slider.maximumTrackTintColor = .systemGray4
        return slider
    }()

    private let loadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Загрузить анимацию", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 20
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        startPlaying()
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
            print("⚠️ Имя сцены не задано.")
            return
        }
        animationView.preload(scenes: [scene]) { [weak self] in
            guard let self = self else { return }
            self.animationView.play(scene: scene, loop: true)
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
        animationView.playExternal(from: url, loop: true) { [weak self] result in
            switch result {
            case .success:
                print("✅ Успешная загрузка файла")
            case .failure(let error):
                self?.showError("Не удалось загрузить файл: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = .white

        cameraSlider.minimumValue = -Float.pi
        cameraSlider.maximumValue = Float.pi
        cameraSlider.value = 0
        cameraSlider.minimumTrackTintColor = .red
        cameraSlider.maximumTrackTintColor = .green
        cameraSlider.addTarget(self, action: #selector(cameraSliderChanged(_:)), for: .valueChanged)

        elevationSlider.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        elevationSlider.addTarget(self, action: #selector(elevationSliderChanged(_:)), for: .valueChanged)

        lightSlider.addTarget(self, action: #selector(lightSliderChanged(_:)), for: .valueChanged)
        updateLightTitle(with: lightSlider.value)

        loadButton.addTarget(self, action: #selector(loadButtonTapped), for: .touchUpInside)

        view.addSubview(azimuthLabel)
        view.addSubview(elevationLabel)
        view.addSubview(animationView)
        view.addSubview(cameraSlider)
        view.addSubview(elevationSlider)
        view.addSubview(lightTitleLabel)
        view.addSubview(lightSlider)
        view.addSubview(loadButton)

        bindAnimationView()
        setupConstraints()
    }

    // MARK: - Formatting

    /// Форматирует значение в радианах как коэффициент при π: 0.50π, -0.25π, 1.00π.
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

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func cameraSliderChanged(_ sender: UISlider) {
        animationView.setCameraAzimuthOffset(sender.value)
        updateAzimuthLabel(sender.value)
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
        // Пользователь закрыл пикер без выбора — ничего не делаем.
    }
}

// MARK: - Layout

private extension ViewController {
    func setupConstraints() {
        [
            azimuthLabel,
            elevationLabel,
            animationView,
            cameraSlider,
            elevationSlider,
            lightTitleLabel,
            lightSlider,
            loadButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            // Тайтлы друг под другом, прижаты к левому краю, над animationView.
            azimuthLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 25),
            azimuthLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            azimuthLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            elevationLabel.topAnchor.constraint(equalTo: azimuthLabel.bottomAnchor, constant: 2),
            elevationLabel.leadingAnchor.constraint(equalTo: azimuthLabel.leadingAnchor),
            elevationLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            animationView.topAnchor.constraint(equalTo: elevationLabel.bottomAnchor, constant: 15),
            animationView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            animationView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
            animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor),

            cameraSlider.topAnchor.constraint(equalTo: animationView.bottomAnchor, constant: 5),
            cameraSlider.centerXAnchor.constraint(equalTo: animationView.centerXAnchor),
            cameraSlider.widthAnchor.constraint(equalTo: animationView.widthAnchor),

            elevationSlider.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            elevationSlider.centerYAnchor.constraint(equalTo: animationView.centerYAnchor),
            elevationSlider.widthAnchor.constraint(equalToConstant: 200),
            elevationSlider.heightAnchor.constraint(equalToConstant: 30),

            lightTitleLabel.topAnchor.constraint(equalTo: cameraSlider.bottomAnchor, constant: 12),
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
