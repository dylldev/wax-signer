import UserNotifications
final class Service: UNNotificationServiceExtension {
    override func didReceive(_ r: UNNotificationRequest, withContentHandler h: @escaping (UNNotificationContent) -> Void) { h(r.content) }
}
