//
//  ActivityData.swift
//  BasicExample-CocoaPods-Aayush
//
//  Created by Aayush Sinha on 3/14/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//
import UIKit
import BoseWearable
import Charts

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
    var sensorType:String=""
    
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
    
    mutating func appendSensorData(timeStamp:SensorTimestamp, vector:Vector, modelDataHandler:ModelDataHandler) {
        var unwrappedTimeStamp:Int64 = 0
        var timeStampDelta = 0
        let millisecToSec = 0.001
        var vector_local = vector
        // Normalize accelerometer values
        var normalization_factor = modelDataHandler.returnSensorDimensionNormalizationValue(name: logFileName + "x")
        vector_local.x /= normalization_factor
        normalization_factor = modelDataHandler.returnSensorDimensionNormalizationValue(name: logFileName + "y")
        vector_local.y /= normalization_factor
        normalization_factor = modelDataHandler.returnSensorDimensionNormalizationValue(name: logFileName + "z")
        vector_local.z /= normalization_factor

        if self.prevDataTimeStamp == 0 &&
            self.maxDataTimeStamp == 0 {
            self.prevDataTimeStamp = timeStamp
        }
        if timeStamp < self.prevDataTimeStamp {
            // Handle wraparounds
            self.maxDataTimeStamp += Int64(65536)
            timeStampDelta = Int(round(Double(Int(timeStamp) + 65535 - Int(self.prevDataTimeStamp))/Double(modelDataHandler.model_sample_period)))
        }
        else {
            timeStampDelta = Int(round(Double(Int(timeStamp) - Int(self.prevDataTimeStamp))/Double(modelDataHandler.model_sample_period)))
        }
        if (timeStampDelta > 10) {
            /*stopDataCollection()
            startDataCollection()*/
        }
        else {
            for index in stride(from: 1, through: timeStampDelta-1, by: 1) {
                let timeStampBase = self.maxDataTimeStamp + Int64(self.prevDataTimeStamp)
                self.dataTimeStamp.append(Double(timeStampBase + Int64(index) * Int64(modelDataHandler.model_sample_period)) * millisecToSec)
                let scale = Double(index)/Double(timeStampDelta)
                let lastX : Double = self.dataX.last ?? 0.0
                let lastY : Double = self.dataY.last ?? 0.0
                let lastZ : Double = self.dataZ.last ?? 0.0
                self.dataX.append(lastX + scale * (vector.x - lastX))
                self.dataY.append(lastY + scale * (vector.y - lastY))
                self.dataZ.append(lastZ + scale * (vector.z - lastZ))
                self.interpolatedDataX.append(lastX + scale * (vector.x - lastX))
                self.interpolatedDataY.append(lastY + scale * (vector.y - lastY))
                self.interpolatedDataZ.append(lastZ + scale * (vector.z - lastZ))
            }
            unwrappedTimeStamp = Int64(timeStamp) + self.maxDataTimeStamp
            self.prevDataTimeStamp = timeStamp
            self.dataTimeStamp.append(Double(unwrappedTimeStamp) * millisecToSec)
            //Buffer stores x, y and z accelerometer data from frames.
            self.dataX.append(vector.x)
            self.dataY.append(vector.y)
            self.dataZ.append(vector.z)
            self.interpolatedDataX.append(0.0)
            self.interpolatedDataY.append(0.0)
            self.interpolatedDataZ.append(0.0)
            self.dataX = self.dataX.suffix(240)
            self.dataY = self.dataY.suffix(240)
            self.dataZ = self.dataZ.suffix(240)
            self.dataTimeStamp = self.dataTimeStamp.suffix(240)
            self.interpolatedDataX = self.interpolatedDataX.suffix(240)
            self.interpolatedDataY = self.interpolatedDataY.suffix(240)
            self.interpolatedDataZ = self.interpolatedDataZ.suffix(240)
        }
    }
    
    func updateSensorGraph() -> LineChartData {
        let sensorLineChart = LineChartData() //This is the object that will be added to the chart
        let line1 : LineChartDataSet = addCurve(curveName : self.dataX, timestamps : self.dataTimeStamp, label : "Data-X", color : NSUIColor.blue)
        let line2 : LineChartDataSet = addCurve(curveName : self.dataY, timestamps : self.dataTimeStamp, label : "Data-Y", color : NSUIColor.red)
        let line3 : LineChartDataSet = addCurve(curveName : self.dataZ, timestamps : self.dataTimeStamp, label : "Data-Z", color : NSUIColor.green)
        let line4 : LineChartDataSet = addCurve(curveName : self.interpolatedDataX, timestamps : self.dataTimeStamp, label : "interpolatedData-X", color : NSUIColor.black)
        let line5 : LineChartDataSet = addCurve(curveName : self.interpolatedDataY, timestamps : self.dataTimeStamp, label : "interpolatedData-X", color : NSUIColor.cyan)
        let line6 : LineChartDataSet = addCurve(curveName : self.interpolatedDataZ, timestamps : self.dataTimeStamp, label : "interpolatedData-Z", color : NSUIColor.yellow)
        
        
        sensorLineChart.addDataSet(line1) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line2) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line3) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line4) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line5) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line6) //Adds the line to the dataSet
        
        return sensorLineChart
    }
    func addCurve(curveName : [Double], timestamps : [Double], label : String, color : NSUIColor) -> LineChartDataSet {
        
        var lineChartEntry  = [ChartDataEntry]() //this is the Array that will eventually be displayed on the graph.
        
        //here is the for loop
        for i in 0..<curveName.count {
            
            let value = ChartDataEntry(x: timestamps[i], y: curveName[i]) // here we set the X and Y status in a data chart entry
            lineChartEntry.append(value) // here we add it to the data set
        }
        
        let line1 = LineChartDataSet(entries: lineChartEntry, label: label) //Here we convert lineChartEntry to a LineChartDataSet
        line1.colors = [color] //Sets the colour to blue
        line1.drawCirclesEnabled = false
        
        return line1
    }
}

class activity{
    
    var aggregatedData:[Double]=[]
    var accel:SensorData
    var gyro:SensorData
    
    init(){
        self.aggregatedData=[]
        let fileStartRecordTimeStamp = getCurrentTimeStamp()
        self.accel = SensorData(initLogFileName:"accel_" + fileStartRecordTimeStamp + ".csv")
        self.gyro = SensorData(initLogFileName:"gyro_" + fileStartRecordTimeStamp + ".csv")
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
    
    func flushDataBuffers() {
        self.accel.flushSensorData()
        self.gyro.flushSensorData()
    }
    
    func updateGraph() -> (LineChartData, LineChartData){
        let accelChart = self.accel.updateSensorGraph()
        let gyroChart = self.gyro.updateSensorGraph()
        
        return (accelChart,gyroChart)
    }
}

func getCurrentTimeStamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH-mm-ss-SSS, yyyy-MM-dd"
    
    let dataString:String =  formatter.string(from: Date())
    return dataString
}
