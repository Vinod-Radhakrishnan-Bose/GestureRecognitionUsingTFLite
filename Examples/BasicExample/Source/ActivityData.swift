//
//  ActivityData.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Aayush Sinha on 3/14/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//
import CoreML
import Foundation

/// A result from invoking the `Interpreter`.
struct SensorData {
    var dataX:[Double]
    var dataY:[Double]
    var dataZ:[Double]
    var dataTimeStamp:[Double]
    var prevDataTimeStamp:UInt16
    var maxDataTimeStamp:Int64
    var interpolatedDataX:[Double]
    var interpolatedDataY:[Double]
    var interpolatedDataZ:[Double]
    
    init(initDataX: [Double]? = [],
         initDataY: [Double]? = [],
         initDataZ: [Double]? = [],
         initDataTimeStamp:[Double]? = [],
         initPrevDataTimeStamp:UInt16=0,
         initMaxDataTimeStamp:Int64=0,
         initInterpolatedDataX:[Double]?=[],
         initInterpolatedDataY:[Double]?=[],
         initInterpolatedDataZ:[Double]?=[]) {
         dataX = initDataX!
         dataY = initDataY!
         dataZ = initDataZ!
         dataTimeStamp = initDataTimeStamp!
         prevDataTimeStamp = initPrevDataTimeStamp
         maxDataTimeStamp = initMaxDataTimeStamp
         interpolatedDataX = initInterpolatedDataX!
         interpolatedDataY = initInterpolatedDataY!
         interpolatedDataZ = initInterpolatedDataZ!
    }
}

class activity{
    
    var accel:SensorData = SensorData()
    var gyro:SensorData = SensorData()
    var mainData:[Double]=[]

    init(){
        self.mainData=[]
    }
}
