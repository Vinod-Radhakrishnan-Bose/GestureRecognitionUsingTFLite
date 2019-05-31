//
//  ActivityData.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Aayush Sinha on 3/14/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//
import CoreML
import Foundation
class activity{
    
    var accelX:[Double]=[]
    var accelY:[Double]=[]
    var accelZ:[Double]=[]
    var accelTimeStamp:[Double]=[]
    var gyroX:[Double]=[]
    var gyroY:[Double]=[]
    var gyroZ:[Double]=[]
    var gyroTimeStamp:[Double]=[]
    var mainData:[Double]=[]
    var prevAccelSensorTimeStamp:UInt16=0
    var prevGyroSensorTimeStamp:UInt16=0
    var maxAccelSensorTimeStamp:Int64=0
    var maxGyroSensorTimeStamp:Int64=0
    var interpolatedAccelX:[Double]=[]
    var interpolatedAccelY:[Double]=[]
    var interpolatedAccelZ:[Double]=[]
    var interpolatedGyroX:[Double]=[]
    var interpolatedGyroY:[Double]=[]
    var interpolatedGyroZ:[Double]=[]

    init(){
        self.accelX=[]
        self.accelY=[]
        self.accelZ=[]
        self.gyroX=[]
        self.gyroY=[]
        self.gyroZ=[]
        self.mainData=[]
        self.maxAccelSensorTimeStamp=0
        self.maxGyroSensorTimeStamp=0
        self.prevGyroSensorTimeStamp=0
        self.prevAccelSensorTimeStamp=0
        self.interpolatedAccelX=[]
        self.interpolatedAccelY=[]
        self.interpolatedAccelZ=[]
        self.interpolatedGyroX=[]
        self.interpolatedGyroY=[]
        self.interpolatedGyroZ=[]
    }   
}
