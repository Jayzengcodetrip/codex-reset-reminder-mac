import CryptoKit
import Foundation

enum AccountResetReceiptCacheError: Error {
    case invalidSavedState
}

/// A local, account-isolated high-water mark from exact official credit grant times.
/// Reading a first snapshot establishes evidence silently; this cache never sends notifications.
final class AccountResetReceiptCache {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotch", isDirectory: true)
            .appendingPathComponent("account-reset-receipts.json")
    }

    private struct Document: Codable {
        var schemaVersion = 1
        var accounts: [String: AccountResetReceipt] = [:]
    }

    private let url: URL
    private let lock = NSLock()

    init(url: URL = AccountResetReceiptCache.defaultURL) {
        self.url = url
    }

    /// A missing account identity must never fall back to the last account's receipt.
    /// Malformed state is left untouched and contributes no evidence.
    func receipt(for accountID: String?, now: Date = .now) -> AccountResetReceipt? {
        guard let key = Self.accountKey(accountID) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let document = try? readDocument(),
              let receipt = document.accounts[key], Self.isPastGrant(receipt.grantedAt, now: now),
              ResetDeliveryEvidence.isGeneralAccountReceipt(receipt) else { return nil }
        return receipt
    }

    /// Empty/consumed-credit snapshots do not erase a receipt. Failed writes never
    /// claim a new persisted receipt, and a corrupt file is never replaced automatically.
    func update(accountID: String?, credits: [ResetCredit], now: Date = .now) throws -> AccountResetReceipt? {
        guard let key = Self.accountKey(accountID) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var document = try readDocument()
        let existing = document.accounts[key]
        var latest = existing.flatMap { ResetDeliveryEvidence.isGeneralAccountReceipt($0) ? $0 : nil }
        for credit in credits {
            guard credit.resetType == "codex_rate_limits", credit.isSupportedByPlan != false,
                  let grant = credit.grantedAt, Self.isPastGrant(grant, now: now) else { continue }
            let candidate = AccountResetReceipt(grantedAt: grant,
                title: Self.nonempty(credit.title), description: Self.nonempty(credit.creditDescription))
            guard ResetDeliveryEvidence.isGeneralAccountReceipt(candidate) else { continue }
            if latest == nil || grant > latest!.grantedAt {
                latest = candidate
            } else if grant == latest?.grantedAt {
                // Sparse later snapshots cannot erase the known receipt context.
                latest = AccountResetReceipt(grantedAt: grant,
                    title: candidate.title ?? latest?.title,
                    description: candidate.description ?? latest?.description)
            }
        }
        if latest != existing, let latest {
            document.accounts[key] = latest
            try writeDocument(document)
        }
        guard let latest, Self.isPastGrant(latest.grantedAt, now: now),
              ResetDeliveryEvidence.isGeneralAccountReceipt(latest) else { return nil }
        return latest
    }

    private static func accountKey(_ accountID: String?) -> String? {
        guard let identity = accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identity.isEmpty else { return nil }
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isPastGrant(_ date: Date, now: Date) -> Bool {
        let timestamp = date.timeIntervalSince1970
        return timestamp.isFinite && timestamp > 0 && timestamp <= now.timeIntervalSince1970
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func readDocument() throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Document()
        }
        guard data.count <= 2_000_000 else { throw AccountResetReceiptCacheError.invalidSavedState }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw AccountResetReceiptCacheError.invalidSavedState }
        guard document.schemaVersion == 1,
              document.accounts.allSatisfy({ key, receipt in
                  key.count == 64 && key.allSatisfy { "0123456789abcdef".contains($0) }
                      && receipt.grantedAt.timeIntervalSince1970.isFinite
                      && receipt.grantedAt.timeIntervalSince1970 > 0
              }) else { throw AccountResetReceiptCacheError.invalidSavedState }
        return document
    }

    private func writeDocument(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2_000_000 else { throw AccountResetReceiptCacheError.invalidSavedState }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
