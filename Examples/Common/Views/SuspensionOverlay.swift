//
//  SuspensionOverlay.swift
//  Common
//
//  Created by Paul Calnan on 2/11/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//

import UIKit

class SuspensionOverlay: UIView {
    private init(parentView: UIView) {
        super.init(frame: parentView.bounds)

        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = UIColor.clear

        let overlay = UIView(frame: parentView.bounds)
        overlay.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        overlay.backgroundColor = UIColor(white: 0, alpha: 0.7)

        let label = UILabel(frame: CGRect.zero)
        label.text = "Wearable Sensor Service Suspended"
        label.textColor = .white
        label.sizeToFit()

        overlay.addSubview(label)
        label.center = overlay.center

        overlay.center = self.center
        addSubview(overlay)

        parentView.addSubview(self)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    static func add(to view: UIView?) -> SuspensionOverlay? {
        guard let view = view else {
            return nil
        }
        return SuspensionOverlay(parentView: view)
    }
}
