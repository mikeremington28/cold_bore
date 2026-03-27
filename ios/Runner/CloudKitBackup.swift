import CloudKit
import Foundation

class CloudKitBackupHandler {
    static let shared = CloudKitBackupHandler()
    private let container = CKContainer.default()
    private let privateDatabase = CKContainer.default().privateCloudDatabase
    private let backupAssetField = "backupAsset"
    private let backupStringField = "backupData" // Legacy fallback
    
    func backupToiCloud(backupData: String, timestamp: String, completion: @escaping (String?) -> Void) {
        let record = CKRecord(recordType: "ColdBoreBackup")
        record["timestamp"] = timestamp

        // Use CKAsset for larger payloads and better stability than a String field.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold_bore_backup_\(UUID().uuidString).json")

        do {
            try backupData.write(to: tempURL, atomically: true, encoding: .utf8)
            record[backupAssetField] = CKAsset(fileURL: tempURL)
            // Keep legacy field for compatibility with older restores.
            record[backupStringField] = backupData
        } catch {
            completion("Backup failed: Unable to prepare backup file")
            return
        }
        
        privateDatabase.save(record) { savedRecord, error in
            try? FileManager.default.removeItem(at: tempURL)
            if let error = error {
                completion("Backup failed: \(error.localizedDescription)")
            } else {
                completion("Backup saved to iCloud successfully")
            }
        }
    }
    
    func restoreFromiCloud(completion: @escaping (String?) -> Void) {
        let query = CKQuery(recordType: "ColdBoreBackup", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        privateDatabase.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                completion(nil)
                return
            }
            
            guard let records = records, !records.isEmpty else {
                completion(nil)
                return
            }
            
            let latestRecord = records.first

            if let asset = latestRecord?[self.backupAssetField] as? CKAsset,
               let fileURL = asset.fileURL,
               let data = try? Data(contentsOf: fileURL),
               let backupData = String(data: data, encoding: .utf8) {
                completion(backupData)
            } else if let backupData = latestRecord?[self.backupStringField] as? String {
                completion(backupData)
            } else {
                completion(nil)
            }
        }
    }
}
