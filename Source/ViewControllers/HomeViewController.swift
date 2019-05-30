//
//  HomeTableViewController.swift
//  BasicExample
//
//  Created by Paul Calnan on 11/26/18.
//  Copyright © 2018 Bose Corporation. All rights reserved.
//

import BoseWearable
import UIKit

class HomeViewController: UITableViewController {

    private var activityIndicator: ActivityIndicator?

    @IBOutlet var autoselectSwitch: UISwitch!

    /// Determine the search mode based on the state of the autoselect switch
    private var mode: DeviceSearchMode {
        return autoselectSwitch.isOn

            // This option only shows the search UI if the most-recently connected device
            // is not found within 5 seconds. If the most-recently connected device is
            // found before 5 seconds has elapsed, it is automatically selected.
            ? .automaticallySelectMostRecentlyConnectedDevice(timeout: 5)

            // This option will always immediately show the search UI.
            : .alwaysShowUI
    }

    //override func viewDidLoad() {
    //    super.viewDidLoad()
    //    versionLabel.text = "BoseWearable \(BoseWearable.formattedVersion)"
    //}

    @IBAction func searchTapped(_ sender: Any) {
        // Block this view controller's UI before showing the modal search.
        activityIndicator = ActivityIndicator.add(to: navigationController?.view)

        // Perform the device search. This may present a view controller on a new
        // UIWindow.
        BoseWearable.shared.startDeviceSearch(mode: mode) { result in
            switch result {
            case .success(let session):
                // A device was selected and a session was created. Show a view
                // controller that will become the session delegate and open the
                // session.
                self.showDeviceInfo(for: session)

            case .failure(let error):
                // An error occurred when performing the search or creating the
                // session. Present an alert showing the error.
                self.show(error)

            case .cancelled:
                // The user cancelled the search operation.
                break
            }

            // An error occurred when performing the search or creating the
            // session. Present an alert showing the error.
            self.activityIndicator?.removeFromSuperview()
        }
    }

    @IBAction func useSimulatedDeviceTapped(_ sender: Any) {
        // Instead of using a session for a remote device, create a session for a
        // simulated device.
        showDeviceInfo(for: BoseWearable.shared.createSimulatedWearableDeviceSession())
    }

    private func showDeviceInfo(for session: WearableDeviceSession) {
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "DataCollectionViewController") as? DataCollectionViewController else {
            fatalError("Cannot instantiate view controller")
        }

        vc.session = session
        show(vc, sender: self)
    }
}
