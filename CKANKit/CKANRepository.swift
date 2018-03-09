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
    var ckanFiles: [CKANFile]?

    // MARK: URLs
    private let zipFileName = "ckan_meta_master.zip"
    private let cachePlistFileName = "ckan_repository_cache.plist"
    private let unzippedDirectoryName = "ckan_meta_master"
    private var zipFileURL: URL { return workingDirectory.appendingPathComponent(zipFileName) }
    private var cachePlistURL: URL { return workingDirectory.appendingPathComponent(cachePlistFileName) }
    private var unzippedDirectoryURL: URL { return workingDirectory.appendingPathComponent(unzippedDirectoryName) }

    // MARK: Private
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    // MARK: - Initialization
    init(inDirectory workingDirectory: URL, withDownloadURL downloadURL: URL? = nil) {
        self.workingDirectory = workingDirectory

        if let downloadURL = downloadURL {
            self.downloadURL = downloadURL
        } else {
            self.downloadURL = URL(string: "https://github.com/KSP-CKAN/CKAN-meta/archive/master.zip")!
        }

        createDirectoryIfNotExists(workingDirectory)
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

        var newCkanFiles = [CKANFile]()
        for fileURL in allFileURLs {
            if fileURL.pathExtension == "ckan" {
                do {
                    let fileData = try Data(contentsOf: fileURL)
                    let ckanFile = try decoder.decode(CKANFile.self, from: fileData)
                    newCkanFiles.append(ckanFile)
                } catch let error {
                    print(error)
                    fatalError()
                }
            }
            progress?.completedUnitCount += 1
        }

        print("Decoding complete! \(newCkanFiles.count) files decoded")
        ckanFiles = newCkanFiles
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

    /// Burp the current CKAN Files into a cache file
    func saveToCache() {
        // Not implemented
    }

    /// Unburp the contents of the cache file into the ckanFiles array
    func readRepositoryArchiveFromCache() -> Bool {
        // Not implemented
        return false
    }

}
