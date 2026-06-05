import Flutter
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let healthStore = HKHealthStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "health_sync_bridge",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "isAvailable":
          result(HKHealthStore.isHealthDataAvailable())
        case "requestAccess":
          self.requestAccess(result: result)
        case "sync":
          self.readSnapshot(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestAccess(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(false)
      return
    }

    let types: Set<HKObjectType> = [
      HKObjectType.quantityType(forIdentifier: .stepCount)!,
      HKObjectType.quantityType(forIdentifier: .heartRate)!,
      HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    ]

    healthStore.requestAuthorization(toShare: [], read: types) { success, _ in
      DispatchQueue.main.async {
        result(success)
      }
    }
  }

  private func readSnapshot(result: @escaping FlutterResult) {
    let group = DispatchGroup()
    let now = Date()
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

    var steps: Int?
    var heartRate: Int?
    var sleepHours: Double?

    group.enter()
    readSteps(start: startOfDay, end: now) { value in
      steps = value
      group.leave()
    }

    group.enter()
    readHeartRate(start: yesterday, end: now) { value in
      heartRate = value
      group.leave()
    }

    group.enter()
    readSleepHours(start: yesterday, end: now) { value in
      sleepHours = value
      group.leave()
    }

    group.notify(queue: .main) {
      result([
        "steps": steps as Any,
        "heartRateBpm": heartRate as Any,
        "sleepHours": sleepHours as Any,
        "recordedAt": Int(now.timeIntervalSince1970 * 1000),
      ])
    }
  }

  private func readSteps(start: Date, end: Date, completion: @escaping (Int?) -> Void) {
    guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
      completion(nil)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKStatisticsQuery(
      quantityType: type,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum
    ) { _, stats, _ in
      let value = stats?.sumQuantity()?.doubleValue(for: .count())
      completion(value != nil && value! > 0 ? Int(value!) : nil)
    }
    healthStore.execute(query)
  }

  private func readHeartRate(start: Date, end: Date, completion: @escaping (Int?) -> Void) {
    guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
      completion(nil)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let query = HKSampleQuery(
      sampleType: type,
      predicate: predicate,
      limit: 1,
      sortDescriptors: [sort]
    ) { _, samples, _ in
      guard let sample = samples?.first as? HKQuantitySample else {
        completion(nil)
        return
      }
      let unit = HKUnit.count().unitDivided(by: .minute())
      let value = sample.quantity.doubleValue(for: unit)
      completion(value > 0 ? Int(value.rounded()) : nil)
    }
    healthStore.execute(query)
  }

  private func readSleepHours(start: Date, end: Date, completion: @escaping (Double?) -> Void) {
    guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      completion(nil)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKSampleQuery(
      sampleType: type,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, _ in
      let asleep = samples?
        .compactMap { $0 as? HKCategorySample }
        .filter { sample in
          if #available(iOS 16.0, *) {
            return sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
              sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
              sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
              sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
          }
          return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
        } ?? []

      let seconds = asleep.reduce(0.0) { total, sample in
        total + sample.endDate.timeIntervalSince(sample.startDate)
      }
      completion(seconds > 0 ? seconds / 3600.0 : nil)
    }
    healthStore.execute(query)
  }
}
