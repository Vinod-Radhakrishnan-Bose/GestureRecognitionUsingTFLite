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
    
    init(){
        self.aggregatedData=[]
        self.accel = SensorData(initDataType:"accel")
        self.gyro = SensorData(initDataType:"gyro")
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


