import CloudKit
import Foundation

class CloudKitBackupHandler {
    static let shared = CloudKitBackupHandler()
    private let container = CKContainer.default()
    private let privateDatabase = CKContainer.default().privateCloudDatabase
    
    func backupToiCloud(backupData: String, timestamp: String, completion: @escaping (String?) -> Void) {
        let record = CKRecord(recordType: "ColdBoreBackup")
        record["backupData"] = backupData
        record["timestamp"] = timestamp
        
        privateDatabase.save(record) { savedRecord, error in
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
            if let backupData = latestRecord?["backupData"] as? String {
                completion(backupData)
            } else {
                completion(nil)
            }
        }
    }
}
