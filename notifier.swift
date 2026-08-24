import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let args = CommandLine.arguments

        if args.count >= 3 {
            postNotification(title: args[1], body: args[2], url: args.count >= 4 ? args[3] : nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSApp.terminate(nil)
            }
        }
    }

    func postNotification(title: String, body: String, url: String?) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            guard granted else {
                fputs("Notification permission denied. Enable in System Settings > Notifications > AI Syncing.\n", stderr)
                NSApp.terminate(nil)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let url = url {
                content.userInfo = ["url": url]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    fputs("Notification error: \(error)\n", stderr)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
