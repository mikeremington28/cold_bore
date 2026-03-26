import CloudKit
import Foundation

class CloudKitBackupHandler {
    static let shared = CloudKitBackupHandler()
    
    private let container = CKContainer.default()
    private let database: CKDatabase
    
    private init() {
        self.database = container.privateCloudDatabase
    }
    
    func backupToiCloud(backupData: String, timestamp: String, completion: @escaping (String) -> Void) {
        let record = CKRecord(recordType: "ColdBoreBackup")
        record["backupData"] = backupData as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        record["deviceName"] = UIDevice.current.name as CKRecordValue
        
        database.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "CloudKit backup failed: \(error.localizedDescription)"
                    print(errorMsg)
                    completion(errorMsg)
                } else if let savedRecord = savedRecord {
                    let successMsg = "Backup saved to iCloud: \(savedRecord.recordID.recordName)"
                    print(successMsg)
                    completion(successMsg)
                } else {
                    completion("Backup completed but no record returned")
                }
            }
        }
    }
    
    func restoreFromiCloud(completion: @escaping (String?) -> Void) {
        let query = CKQuery(recordType: "ColdBoreBackup", predicate: NSPredicate(value: true))
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        query.sortDescriptors = [sortDescriptor]
        
        database.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "CloudKit restore failed: \(error.localizedDescription)"
                    print(errorMsg)
                    completion(nil)
                } else if let records = records, let latestRecord = records.first,
                          let backupData = latestRecord["backupData"] as? String {
                    print("Restored backup from iCloud")
                    completion(backupData)
                } else {
                    print("No backups found in iCloud")
                    completion(nil)
                }
            }
        }
    }
}
