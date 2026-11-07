//
//  SceneCache.swift
//  Test3D
//
//  Created by  Alexander Fedoseev on 07.11.2026.
//


import Foundation
import RealityKit

final class SceneCache {

    static let shared = SceneCache()

    private var cache: [String: Entity] = [:]
    private let lock = NSLock()
    private var isLoading = false
    private var pendingCompletions: [() -> Void] = []

    private init() {}

    // MARK: - Preload (бандл)

    func preload(names: Set<String>, completion: (() -> Void)? = nil) {
        lock.lock()

        let missing = names.filter { cache[$0] == nil }
        if missing.isEmpty {
            lock.unlock()
            DispatchQueue.main.async { completion?() }
            return
        }

        if let completion = completion {
            pendingCompletions.append(completion)
        }

        if isLoading {
            lock.unlock()
            return
        }

        isLoading = true
        lock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            var loaded: [String: Entity] = [:]
            for name in missing {
                if let entity = await self.loadEntity(named: name) {
                    loaded[name] = entity
                } else {
                    print("❌ Не удалось загрузить сцену \(name) из бандла.")
                }
            }

            self.store(loaded)
        }
    }

    private func loadEntity(named name: String) async -> Entity? {
        do {
            return try await Entity(named: name, in: .main)
        } catch {
            print("⚠️ Entity(named: \"\(name)\"): \(error)")
            return nil
        }
    }

    // MARK: - Load from external URL (папка на телефоне)

    /// Загружает сущность из внешнего URL (например, из Files.app).
    /// Копирует файл в песочницу, чтобы security-scoped URL можно было закрыть.
    func loadEntity(
        from externalURL: URL,
        completion: @escaping (Result<Entity, Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let accessing = externalURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    externalURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // 1. Копируем файл во временную папку (или Documents).
                let localURL = try self.copyToSandbox(externalURL)

                // 2. Загружаем Entity из локального URL.
                let entity = try await Entity(contentsOf: localURL)

                // 3. Кэшируем по имени файла без расширения.
                let cacheKey = localURL.deletingPathExtension().lastPathComponent
                self.lock.lock()
                self.cache[cacheKey] = entity
                self.lock.unlock()

                await MainActor.run {
                    completion(.success(entity))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func copyToSandbox(_ sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = fm.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension(ext)

        // Если файл уже скопирован — используем его.
        if fm.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    // MARK: - Access

    func scene(named name: String) -> Entity? {
        lock.lock()
        defer { lock.unlock() }
        return cache[name]
    }

    private func store(_ loaded: [String: Entity]) {
        lock.lock()
        for (key, value) in loaded {
            cache[key] = value
        }
        isLoading = false
        let callbacks = pendingCompletions
        pendingCompletions.removeAll()
        lock.unlock()

        DispatchQueue.main.async {
            callbacks.forEach { $0() }
        }
    }
}
