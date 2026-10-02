import CryptoKit
import Darwin
import Foundation

struct BridgeHelperInstaller {
    var bundledHelperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NudgeBridge", isDirectory: false)
    }

    var installedHelperURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nudge/bin/NudgeBridge", isDirectory: false)
    }

    func install() throws -> URL {
        let source = bundledHelperURL
        let destination = installedHelperURL
        var sourceInfo = stat()
        guard lstat(source.path, &sourceInfo) == 0,
              (sourceInfo.st_mode & S_IFMT) == S_IFREG,
              sourceInfo.st_uid == getuid() || sourceInfo.st_uid == 0,
              access(source.path, X_OK) == 0 else { throw HelperInstallError.missingHelper }

        let directory = destination.deletingLastPathComponent()
        try ensurePrivateDirectory(directory)
        var destinationInfo = stat()
        if lstat(destination.path, &destinationInfo) == 0 {
            guard (destinationInfo.st_mode & S_IFMT) == S_IFREG, destinationInfo.st_uid == getuid() else {
                throw HelperInstallError.unsafeDestination
            }
        } else if errno != ENOENT {
            throw HelperInstallError.unsafeDestination
        }

        let temporary = directory.appendingPathComponent(".NudgeBridge-\(UUID().uuidString)")
        guard linkOrCopy(source.path, temporary.path) == 0 else { throw HelperInstallError.copyFailed }
        defer { _ = unlink(temporary.path) }
        guard chmod(temporary.path, mode_t(S_IRUSR | S_IWUSR | S_IXUSR)) == 0 else { throw HelperInstallError.copyFailed }
        let sourceHash = try digest(at: source)
        let installedHash = try digest(at: temporary)
        guard sourceHash == installedHash else { throw HelperInstallError.copyFailed }
        guard rename(temporary.path, destination.path) == 0 else { throw HelperInstallError.copyFailed }
        let directoryDescriptor = open(directory.path, O_RDONLY)
        if directoryDescriptor >= 0 { _ = fsync(directoryDescriptor); Darwin.close(directoryDescriptor) }
        return destination
    }

    private func linkOrCopy(_ source: String, _ destination: String) -> Int32 {
        // Copy avoids a hard link into the app bundle, whose updater may replace in place.
        do {
            try FileManager.default.copyItem(atPath: source, toPath: destination)
            return 0
        } catch {
            return -1
        }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw HelperInstallError.unsafeDestination }
            guard chmod(url.path, mode_t(S_IRWXU)) == 0 else { throw HelperInstallError.unsafeDestination }
            var verified = stat()
            guard lstat(url.path, &verified) == 0,
                  (verified.st_mode & S_IFMT) == S_IFDIR, verified.st_uid == getuid(),
                  verified.st_mode & 0o777 == 0o700 else { throw HelperInstallError.unsafeDestination }
            return
        }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { throw HelperInstallError.unsafeDestination }
        guard chmod(url.path, mode_t(S_IRWXU)) == 0 else { throw HelperInstallError.unsafeDestination }
    }

    private func digest(at url: URL) throws -> Data {
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch { throw HelperInstallError.copyFailed }
        return Data(SHA256.hash(data: data))
    }
}

enum HelperInstallError: Error, LocalizedError {
    case missingHelper
    case unsafeDestination
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .missingHelper: "NudgeBridge is missing from the app bundle. Rebuild Nudge before installing hooks."
        case .unsafeDestination: "The Nudge helper path is not a safe user-owned directory or file."
        case .copyFailed: "Nudge could not install a verified bridge helper."
        }
    }
}
