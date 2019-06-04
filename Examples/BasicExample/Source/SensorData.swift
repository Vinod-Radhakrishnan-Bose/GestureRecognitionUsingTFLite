//
//  ActivityData.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Aayush Sinha on 3/14/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//
import UIKit

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
    var logFileName = "" // Filename for logging sensor data
    var logFileURL:URL? = nil
    
    private var firstWriteToLogFile:Bool = true
    
    init(initDataX: [Double]? = [],
        initDataY: [Double]? = [],
        initDataZ: [Double]? = [],
        initDataTimeStamp:[Double]? = [],
        initPrevDataTimeStamp:UInt16=0,
        initMaxDataTimeStamp:Int64=0,
        initInterpolatedDataX:[Double]?=[],
        initInterpolatedDataY:[Double]?=[],
        initInterpolatedDataZ:[Double]?=[],
        initLogFileName:String) {
        dataX = initDataX!
        dataY = initDataY!
        dataZ = initDataZ!
        dataTimeStamp = initDataTimeStamp!
        prevDataTimeStamp = initPrevDataTimeStamp
        maxDataTimeStamp = initMaxDataTimeStamp
        interpolatedDataX = initInterpolatedDataX!
        interpolatedDataY = initInterpolatedDataY!
        interpolatedDataZ = initInterpolatedDataZ!
        logFileName = initLogFileName
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as NSURL
        logFileURL = documentDirectory.appendingPathComponent(logFileName)
        firstWriteToLogFile = true
    }

    mutating func flushSensorData() {
        dataX.removeAll()
        dataY.removeAll()
        dataZ.removeAll()
        dataTimeStamp.removeAll()
        prevDataTimeStamp = 0
        maxDataTimeStamp = 0
        interpolatedDataX.removeAll()
        interpolatedDataY.removeAll()
        interpolatedDataZ.removeAll()
    }
    
    mutating func writeToLogFile(txt:String)  {
        if(firstWriteToLogFile)
        {
            var txt_string = self.writeLogFileHeader() + txt
            let data = Data(txt_string.utf8)
            firstWriteToLogFile = false
            do {
                try data.write(to: logFileURL!, options: .atomic)
            } catch {
                print(error)
            }
        }
        else
        {
            do {
                let fileHandle = try FileHandle(forWritingTo: logFileURL!)
                fileHandle.seekToEndOfFile()
                fileHandle.write(txt.data(using: .utf8)!)
                fileHandle.closeFile()
            } catch {
                print("Error writing to file \(error)")
            }
        }
    }
    func writeLogFileHeader() -> String {
        var dataHeader:String = ""
        dataHeader += "timeStamp (ms), "
        dataHeader += "X, "
        dataHeader += "Y, "
        dataHeader += "Z,"
        dataHeader += "iPhone X,"
        dataHeader += "iPhone Y,"
        dataHeader += "iPhone Z \n"
        
        return dataHeader
    }
}

class activity{
    
    var aggregatedData:[Double]=[]
    var accel:SensorData
    var gyro:SensorData
    
    init(){
        self.aggregatedData=[]
        let fileStartRecordTimeStamp = getCurrentTimeStamp()
        self.accel = SensorData(initLogFileName:"Accel_" + fileStartRecordTimeStamp + ".csv")
        self.gyro = SensorData(initLogFileName:"Gyro_" + fileStartRecordTimeStamp + ".csv")
    }
    
    func returnSensorDimension(name:String)->[Double] {
        var array:[Double]=[]
        switch name {
        case "accel_x":
            array = self.accel.dataX
        case "accel_y":
            array = self.accel.dataY
        case "accel_z":
            array = self.accel.dataZ
        case "gyro_x":
            array = self.gyro.dataX
        case "gyro_y":
            array = self.gyro.dataY
        case "gyro_z":
            array = self.gyro.dataZ
        default:
            array = []
        }
        return array
    }
}

func getCurrentTimeStamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH-mm-ss-SSS, yyyy-MM-dd"
    
    let dataString:String =  formatter.string(from: Date())
    return dataString
}
