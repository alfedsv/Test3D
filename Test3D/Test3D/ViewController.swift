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

    private let animationView = AnimationView()
    private let cameraSlider = UISlider()

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
                print("Успешная загрузка файла")
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

        loadButton.addTarget(self, action: #selector(loadButtonTapped), for: .touchUpInside)

        view.addSubview(animationView)
        view.addSubview(cameraSlider)
        view.addSubview(loadButton)

        setupConstraints()
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func cameraSliderChanged(_ sender: UISlider) {
        animationView.setCameraAzimuthOffset(sender.value)
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
        [animationView, cameraSlider, loadButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            animationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 35),
            animationView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            animationView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor),

            cameraSlider.topAnchor.constraint(equalTo: animationView.bottomAnchor, constant: 12),
            cameraSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            cameraSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            loadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            loadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            loadButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
