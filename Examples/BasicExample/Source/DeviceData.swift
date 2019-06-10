//
//  DeviceData.swift
//  BasicExample
//
//  Created by Vinod Radhakrishnan on 6/4/19.
//  Copyright © 2019 Bose Corporation. All rights reserved.
//
import Charts

class DeviceData{
    
    var aggregatedData:[Double]=[]
    var accel:SensorData
    var gyro:SensorData
    var logFileName = "" // Filename for logging sensor data
    var logFileURL:URL? = nil

    private var firstWriteToLogFile:Bool = true
    
    init(){
        self.aggregatedData=[]
        self.accel = SensorData(initDataType:"accel")
        self.gyro = SensorData(initDataType:"gyro")
        let fileStartRecordTimeStamp = getCurrentTimeStamp()
        logFileName = "inference_data_" + fileStartRecordTimeStamp + ".csv"
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as NSURL
        logFileURL = documentDirectory.appendingPathComponent(logFileName)
        firstWriteToLogFile = true    }
    
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
    
    func aggregateData(sensorDimOrdering : [String], numSamplesPerSensorDim : Int) {
        aggregatedData = []
        var inferenceData:String = ""
        for sampleIndex in 0..<numSamplesPerSensorDim {
            for index in 0..<sensorDimOrdering.count {
                let arr = returnSensorDimension(name:sensorDimOrdering[index])
                let dataPoint = arr[arr.count - numSamplesPerSensorDim + sampleIndex]
                aggregatedData.append(dataPoint)
                inferenceData += "\(String(describing: dataPoint)),"
            }
        }
        inferenceData += "\n"
        self.writeToLogFile(txt: inferenceData)
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
    
    func writeToLogFile(txt:String)  {
        if(firstWriteToLogFile)
        {
            var txt_string = txt
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
}


