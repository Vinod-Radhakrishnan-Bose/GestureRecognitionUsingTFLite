//
//  SensorDim.swift
//  BasicExample
//
//  Created by Vinod Radhakrishnan on 6/6/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//

import Foundation
import Charts

protocol SensorDim {
    var name:String {get set}
    var data:[Double] {get set}
    var interpolatedData:[Double] {get set}
    func initialize(name: String)
    func appendData(currentWrappedTimeStamp:Int16, prevWrappedTimeStamp:Int16, baseTimeStamp:Int64, desiredSamplePeriod:Int)
    func normalizeData(minValue:Double, maxValue:Double)
    func addLines() -> (LineChartDataSet, LineChartDataSet)
}
