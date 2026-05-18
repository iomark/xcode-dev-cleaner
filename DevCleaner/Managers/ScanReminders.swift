//
//  ScanReminders.swift
//  DevCleaner
//
//  Created by Konrad Kołakowski on 11.05.2018.
//  Copyright © 2018 One Minute Games. All rights reserved.
//
//  DevCleaner is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 3 of the License, or
//  (at your option) any later version.
//
//  DevCleaner is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with DevCleaner.  If not, see <http://www.gnu.org/licenses/>.

import Foundation
import UserNotifications

public final class ScanReminders {
    // MARK: Types
    public enum Period: Int {
        case everyWeek, every2weeks, everyMonth, every2Months
        
        private var dateComponents: DateComponents {
            var result = DateComponents()
            
            switch self {
                case .everyWeek:
                    result.day = 7
                case .every2weeks:
                    result.day = 7 * 2
                case .everyMonth:
                    result.month = 1
                case .every2Months:
                    result.month = 2
            }
            
            return result
        }
        
        internal var repeatInterval: DateComponents {
            var result = DateComponents()
            
            #if DEBUG
            if Preferences.shared.envKeyPresent(key: "DCNotificationsTest") {
                result.minute = 3 // for debug we change our periods to three minutes
            } else {
                result = self.dateComponents
            }
            #else
            result = self.dateComponents
            #endif
            
            return result
        }
    }
    
    // MARK: Properties
    public static var dateOfNextReminder: Date? {
        let notificationCenter = UNUserNotificationCenter.current()
        var nextDate: Date?
        let semaphore = DispatchSemaphore(value: 0)
        
        notificationCenter.getPendingNotificationRequests { requests in
            let reminderRequests = requests.filter { $0.identifier.hasPrefix(reminderIdentifier) }
            nextDate = reminderRequests.compactMap { nextTriggerDate(from: $0.trigger) }.min()
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        return nextDate
    }
    
    // MARK: Constants
    private static let reminderIdentifier = "com.oneminutegames.DevCleaner.scanReminder"
    private static let reminderCategoryIdentifier = "com.oneminutegames.DevCleaner.scanReminder.category"
    private static let scanActionIdentifier = "com.oneminutegames.DevCleaner.scanReminder.scan"
    private static let dismissActionIdentifier = "com.oneminutegames.DevCleaner.scanReminder.dismiss"
    private static let scheduledReminderLimit = 52
    
    // MARK: Manage reminders
    public static func scheduleReminder(period: Period) {
        let notificationCenter = UNUserNotificationCenter.current()
        
        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
                case .authorized, .provisional:
                    scheduleAuthorizedReminder(period: period, notificationCenter: notificationCenter)
                case .notDetermined:
                    notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        guard granted else {
                            return
                        }
                        
                        scheduleAuthorizedReminder(period: period, notificationCenter: notificationCenter)
                    }
                default:
                    break
            }
        }
    }
    
    public static func disableReminder() {
        let notificationCenter = UNUserNotificationCenter.current()
        
        notificationCenter.getPendingNotificationRequests { requests in
            let identifiers = reminderIdentifiers(from: requests)
            guard !identifiers.isEmpty else {
                return
            }
            
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    // MARK: Helpers
    private static func scheduleAuthorizedReminder(period: Period, notificationCenter: UNUserNotificationCenter) {
        notificationCenter.getPendingNotificationRequests { requests in
            let identifiers = reminderIdentifiers(from: requests)
            
            if !identifiers.isEmpty {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
            
            registerCategoryIfNeeded(notificationCenter: notificationCenter)
            
            let content = UNMutableNotificationContent()
            content.title = "Scan Xcode cache?"
            content.body = "It's been a while since your last scan, check if you can reclaim some storage."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = reminderCategoryIdentifier
            
            let scheduledDates = scheduledReminderDates(period: period, count: scheduledReminderLimit)
            
            for (index, scheduledDate) in scheduledDates.enumerated() {
                let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let identifier = "\(reminderIdentifier).\(index)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                
                notificationCenter.add(request)
            }
        }
    }
    
    private static func registerCategoryIfNeeded(notificationCenter: UNUserNotificationCenter) {
        let scanAction = UNNotificationAction(identifier: scanActionIdentifier, title: "Scan", options: [.foreground])
        let dismissAction = UNNotificationAction(identifier: dismissActionIdentifier, title: "Close", options: [])
        let category = UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [scanAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
    }
    
    private static func scheduledReminderDates(period: Period, count: Int) -> [Date] {
        var dates = [Date]()
        var nextDate = Date()
        
        for _ in 0..<count {
            guard let scheduledDate = Calendar.current.date(byAdding: period.repeatInterval, to: nextDate) else {
                break
            }
            
            dates.append(scheduledDate)
            nextDate = scheduledDate
        }
        
        return dates
    }
    
    private static func reminderIdentifiers(from requests: [UNNotificationRequest]) -> [String] {
        return requests.compactMap { request in
            guard request.identifier.hasPrefix(reminderIdentifier) else {
                return nil
            }
            
            return request.identifier
        }
    }

    private static func nextTriggerDate(from trigger: UNNotificationTrigger?) -> Date? {
        guard let trigger = trigger else {
            return nil
        }

        if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }

        if let timeTrigger = trigger as? UNTimeIntervalNotificationTrigger {
            return Date(timeIntervalSinceNow: timeTrigger.timeInterval)
        }

        return nil
    }
}
