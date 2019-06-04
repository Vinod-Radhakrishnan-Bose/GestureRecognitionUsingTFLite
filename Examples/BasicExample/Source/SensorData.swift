//
//  ActivityData.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Aayush Sinha on 3/14/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//

/// A result from invoking the `Interpreter`.
struct SensorData {
    var dataX:[Double] // array for storing X-dimension of sensor data
    var dataY:[Double] // Y-dimension and
    var dataZ:[Double] // Z-dimension
    var dataTimeStamp:[Double] // array for unwrapped timestamps corresponding to sensor data
    var prevDataTimeStamp:UInt16 // array for wrapped timestamp for previous data point. Used
                                 // to detect wraparounds in sensor timestamp
    var maxDataTimeStamp:Int64   // unwrapped base timestamp for historical data. This will be
                                 // added to the wrapped timestamp to create the unwrapped timestamp
                                 // for each new data point
    var interpolatedDataX:[Double] // Array for storing interpolated sensor data X-dimension for Debug purposes
    var interpolatedDataY:[Double] // Y-dimension interpolated data and
    var interpolatedDataZ:[Double] // Z-dimension interpolated data.
    
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
    var aggregatedData:[Double]=[]

    init(){
        self.aggregatedData=[]
    }
}
