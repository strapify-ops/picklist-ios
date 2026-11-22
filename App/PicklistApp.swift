import SwiftUI
import UIKit

/// Strapify Picklist for iPhone: a native shell around picklist.strapify.com.au.
/// Everything on screen is the live web picklist, so a picklist deploy updates the app
/// with no new build. The shell adds Apple's own barcode scanner (VisionKit: real autofocus
/// and macro, which the web camera on iPhone never gets) and lays out like the Home Screen
/// PWA on every screen, including the iPhone Duo folded and open.
@main
struct PicklistApp: App {
    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea()   // full screen, folded or open; the page handles safe areas
        }
    }
}

enum Config {
    static let start = URL(string: "https://picklist.strapify.com.au/")!
    /// Pages that stay inside the app (the picklist and its CRM sign-in); everything else opens outside.
    static let ownHosts: Set<String> = ["picklist.strapify.com.au", "crm.strapify.com.au"]

    static func isOwnHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ownHosts.contains(host)
    }
}
