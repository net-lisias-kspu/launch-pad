//
//  CKANRepository.swift
//  Launch Pad
//
//  Created by Daniel Jilg on 03.03.18.
//  Copyright © 2018 breakthesystem. All rights reserved.
//

import Foundation

public class CKANRepository {

    // MARK: - Properties
    // MARK: Configuration
    let downloadURL: URL
    let workingDirectory: URL

    // MARK: CKANFiles
    var modules: [CKANModule]?

    // MARK: URLs
    private let zipFileName = "ckan_meta_master.zip"
    private let cacheFileName = "ckan_repository_cache.json"
    private let unzippedDirectoryName = "ckan_meta_master"
    private var zipFileURL: URL { return workingDirectory.appendingPathComponent(zipFileName) }
    private var cacheFileURL: URL { return workingDirectory.appendingPathComponent(cacheFileName) }
    private var unzippedDirectoryURL: URL { return workingDirectory.appendingPathComponent(unzippedDirectoryName) }

    // MARK: - Notifications
    private var notificationCenter = NotificationCenter.default
    static let allModulesUpdatedNotification = Notification.Name("allModulesUpdated")

    private func postAllModulesUpdatedNotification() {
        notificationCenter.post(name: CKANRepository.allModulesUpdatedNotification, object: self)
    }

    // MARK: Private
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    // MARK: - Initialization
    init(inDirectory workingDirectory: URL, withDownloadURL downloadURL: URL? = nil) {
        // Initialize Properties
        self.workingDirectory = workingDirectory
        self.downloadURL = downloadURL ?? URL(string: "https://github.com/KSP-CKAN/CKAN-meta/archive/master.zip")!

        // Prepare Working Directory
        createDirectoryIfNotExists(workingDirectory)

        // Check for Repository Cache
        readRepositoryArchiveFromCache()
    }

    func repositoryZIPFileExists() -> Bool {
        return fileManager.fileExists(atPath: zipFileURL.path)
    }

    func createDirectoryIfNotExists(_ directoryURL: URL) {
        var isDirectory = ObjCBool(true)
        let directoryExists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        if !(directoryExists && isDirectory.boolValue) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error)
            }
        }
    }

    func downloadRepositoryArchive(callback: @escaping () -> ()) -> Progress {
        let localUrl = zipFileURL
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let request = URLRequest(url: downloadURL)

        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                // Success
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    print("Success: \(statusCode)")
                }

                do {
                    try self.fileManager.copyItem(at: tempLocalUrl, to: localUrl)
                    callback()
                } catch (let writeError) {
                    print("error writing file \(localUrl) : \(writeError)")
                }

            } else {
                print("Failure: \(error?.localizedDescription ?? ":("))")
            }
        }
        task.resume()
        return task.progress
    }

    func unpackRepositoryArchive(progress: Progress? = nil) -> Bool {
        let sourceUrl = zipFileURL
        let destinationUrl = unzippedDirectoryURL

        createDirectoryIfNotExists(destinationUrl)

        do {
            try fileManager.unzipItem(at: sourceUrl, to: destinationUrl, progress: progress)
            return true
        } catch CocoaError.fileWriteFileExists {
            // File Exists
            print("Nothing unpacked, file exists")
        } catch {
            print("Extraction of ZIP archive failed with error:\(error)")
        }
        return false
    }

    func readUnpackedRepositoryArchive(progress: Progress?) {
        let enumerator = fileManager.enumerator(at: unzippedDirectoryURL, includingPropertiesForKeys: [], options: [.skipsHiddenFiles], errorHandler: { (url, error) -> Bool in
            print("directoryEnumerator error at \(url): ", error)
            return true
        })!

        let allFileURLs = enumerator.allObjects as! [URL]
        print("count: ", allFileURLs.count)

        if let progress = progress {
            progress.totalUnitCount = Int64(allFileURLs.count)
        }

        var newModules = [CKANModule]()
        for fileURL in allFileURLs {
            if fileURL.pathExtension == "ckan" {
                do {
                    let fileData = try Data(contentsOf: fileURL)
                    let ckanFile = try decoder.decode(CKANFile.self, from: fileData)
                    let ckanModule = CKANModule(ckanFile: ckanFile)
                    newModules.append(ckanModule)
                } catch let error {
                    print(error)
                    fatalError()
                }
            }
            progress?.completedUnitCount += 1
        }

        print("Decoding complete! \(newModules.count) files decoded")
        modules = newModules.sorted(by: { (lhs, rhs) -> Bool in
            return lhs.name.trimmingCharacters(in: NSCharacterSet.whitespaces) < rhs.name.trimmingCharacters(in: NSCharacterSet.whitespaces)
        })
        saveToCache()
        postAllModulesUpdatedNotification()
    }

    func deleteZipFile() {
        do {
            try fileManager.removeItem(at: zipFileURL)
        } catch {
            print("Deleting ZIP archive failed with error:\(error)")
            fatalError()
        }
    }

    func deleteUnzippedDirectory() {
        do {
            try fileManager.removeItem(at: unzippedDirectoryURL)
        } catch {
            print("Deleting unzipped directory failed with error:\(error)")
        }
    }
}

// MARK: Caching and Restoring from Cache
extension CKANRepository {
    /// Burp the current CKAN Files into a cache file
    func saveToCache() {
        guard let modules = modules else {
            print("Nothing to save, modules is empty")
            return
        }

        let jsonEncoder = JSONEncoder()
        let ckanFiles = modules.map { $0.ckanFile }

        do {
            let data = try jsonEncoder.encode(ckanFiles)
            try data.write(to: cacheFileURL)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    /// Unburp the contents of the cache file into the ckanFiles array
    func readRepositoryArchiveFromCache() {
        do {
            let cacheData = try Data(contentsOf: cacheFileURL)
            let ckanFiles = try decoder.decode([CKANFile].self, from: cacheData)

            var newModules = [CKANModule]()
            for ckanFile in ckanFiles {
                let ckanModule = CKANModule(ckanFile: ckanFile)
                newModules.append(ckanModule)
            }

            modules = newModules
            postAllModulesUpdatedNotification()
        } catch {
            print("Could not get repository from cache:", error)
        }
    }

}
