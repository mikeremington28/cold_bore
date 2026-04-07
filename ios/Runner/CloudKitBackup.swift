import CloudKit
import Foundation

class CloudKitBackupHandler {
    static let shared = CloudKitBackupHandler()
    private let container = CKContainer(identifier: "iCloud.com.remington.coldbore")
    private lazy var privateDatabase = container.privateCloudDatabase
    private let latestBackupRecordId = CKRecord.ID(recordName: "cold_bore_latest_backup")
    private let timestampField = "timestamp"
    private let backupAssetField = "backupAsset"
    private let backupStringField = "backupData" // Legacy fallback
    
    func backupToiCloud(backupData: String, timestamp: String, completion: @escaping (String?) -> Void) {
        // Use CKAsset for larger payloads and better stability than a String field.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold_bore_backup_\(UUID().uuidString).json")

        do {
            try backupData.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            completion("Backup failed: Unable to prepare backup file")
            return
        }

        privateDatabase.fetch(withRecordID: latestBackupRecordId) { [weak self] existingRecord, _ in
            guard let self = self else {
                try? FileManager.default.removeItem(at: tempURL)
                completion("Backup failed: iCloud handler unavailable")
                return
            }

            let record = existingRecord ?? CKRecord(recordType: "ColdBoreBackup", recordID: self.latestBackupRecordId)
            record[self.timestampField] = timestamp
            record[self.backupAssetField] = CKAsset(fileURL: tempURL)
            // Keep legacy field for compatibility with older restores.
            record[self.backupStringField] = backupData

            self.privateDatabase.save(record) { _, error in
                try? FileManager.default.removeItem(at: tempURL)
                if let error = error {
                    completion("Backup failed: \(error.localizedDescription)")
                } else {
                    completion("Backup saved to iCloud successfully")
                }
            }
        }
    }
    
    func restoreFromiCloud(completion: @escaping (String?) -> Void) {
        // Primary path: deterministic latest-record lookup.
        privateDatabase.fetch(withRecordID: latestBackupRecordId) { [weak self] record, _ in
            guard let self = self else {
                completion(nil)
                return
            }

            if let backupData = self.decodeBackupPayload(from: record) {
                completion(backupData)
                return
            }

            // Fallback path for older backups created as many records.
            self.restoreLatestLegacyBackup(completion: completion)
        }
    }

    private func restoreLatestLegacyBackup(completion: @escaping (String?) -> Void) {
        let query = CKQuery(recordType: "ColdBoreBackup", predicate: NSPredicate(value: true))

        privateDatabase.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                debugPrint("iCloud legacy restore query failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let records = records, !records.isEmpty else {
                completion(nil)
                return
            }
            
            let latestRecord = records.max { lhs, rhs in
                self.recordDate(lhs) < self.recordDate(rhs)
            }

            if let backupData = self.decodeBackupPayload(from: latestRecord) {
                completion(backupData)
            } else {
                completion(nil)
            }
        }
    }

    private func recordDate(_ record: CKRecord) -> Date {
        if let raw = record[timestampField] as? String,
           let parsed = ISO8601DateFormatter().date(from: raw) {
            return parsed
        }
        return record.modificationDate ?? record.creationDate ?? Date.distantPast
    }

    private func decodeBackupPayload(from record: CKRecord?) -> String? {
        if let asset = record?[backupAssetField] as? CKAsset,
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let backupData = String(data: data, encoding: .utf8) {
            return backupData
        }

        if let backupData = record?[backupStringField] as? String {
            return backupData
        }

        return nil
    }
}
