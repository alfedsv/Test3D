//
//  ViewModel.swift
//  Test3D
//
//  Created by  Alexander Fedoseev on 07.11.2026.
//

import Foundation

protocol ViewModelProtocol: AnyObject {

    var model: SceneModel { get }

    var onError: ((String) -> Void)? { get set }
    var onUpload: ((URL) -> Void)? { get set }

    /// Передаёт внешний URL (из Files.app) наружу — во ViewController.
    func upload(from url: URL)
}

final class ViewModel: ViewModelProtocol {

    var model: SceneModel = SceneModel(externalURL: nil, name: "lola_rumba_dancing", radiusOrbitMul: 2.0, azimuth: .pi / 8, elevation: 0, scaledCenterMulX: 0, scaledCenterMulY: 0.1, scaledCenterMulZ: 0)

    var onError: ((String) -> Void)?
    var onUpload: ((URL) -> Void)?

    func upload(from url: URL) {
        onUpload?(url)
    }
}
