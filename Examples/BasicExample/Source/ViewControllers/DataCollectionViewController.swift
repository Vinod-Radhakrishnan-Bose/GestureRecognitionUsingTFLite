//
//  DataCollectionViewController.swift
//  Copyright © 2019 Bose Corporation. All rights reserved.
//  Paul Calnan, Hiren, Aayush Sinha

import BoseWearable
import UIKit
import MessageUI
import MediaPlayer
import CoreMotion
import AVFoundation
import CoreML
import Accelerate
import TensorFlowLite
import CoreImage
import Charts
import Yaml

class DataCollectionViewController: UIViewController, MFMailComposeViewControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var accelChart: LineChartView!
    @IBOutlet weak var gyroChart: LineChartView!

    //Get the beep sound
    let systemSoundID: SystemSoundID = 1052
    
    var active:activity = activity()
    
    @IBOutlet weak var timerLabelToShowWordTimer: UILabel!
    @IBOutlet weak var myTimer: UILabel!
    /// Set by the showing/presenting code.
    var session: WearableDeviceSession!
    
    /// Used to block the UI during connection.
    private var activityIndicator: ActivityIndicator?
    
    // We create the SensorDispatch without any reference to a session or a device.
    // We provide a queue on which the sensor data events are dispatched on.
    private let sensorDispatch = SensorDispatch(queue: .main)
    
    /// Retained for the lifetime of this object. When deallocated, deregisters
    /// this object as a WearableDeviceEvent listener.
    private var token: ListenerToken?
    
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var confidenceLabel: UILabel!
        
    @IBOutlet weak var startStopButton: UIButton!
    var fileNameAccel = ""
    var fileURLAccel:URL? = nil
    var firstWriteToAccelFile:Bool = true
    
    var fileNameGyro = ""
    var fileURLGyro:URL? = nil
    var firstWriteToGyroFile:Bool = true
    
    var fileNameRoto = ""
    var fileURLRoto:URL? = nil
    var firstWriteToRotoFile:Bool = true
    
    var dataCollectionStaretd:Bool = false
    
    
    let S3BucketName = "contextual-hearing"
    
    var fileStartRecordTimeStamp:String = ""
    var fileStopRecordTimeStamp:String = ""
    
    var recordWavFileOnly:Bool = false
    var recordingSession:AVAudioSession!
    var audioRecorder: AVAudioRecorder!
    var meteringTimer = Timer()
    var audioRecorderSettings = [String : Int]()
    
    var wavFileURLList = [URL]()
    var wavFileNameList = [String]()
    var wavFileVersion:Int = 1
    var wavFileTimmer = Timer()
    var uploadingWavFileToST:Bool = false
    var wavTableCellSelected:Int?

    let motionManager = CMMotionManager()
    
    var num_values_per_sensor_dimenion = 100
    var sensor_dimension_ordering:[String] = []
    var normalization_value:[Double] = []
    var normalization_values_loaded = false
    var model_sample_period:Int = 20
    
    // Handles all data preprocessing and makes calls to run inference through TfliteWrapper
    private var modelDataHandler: ModelDataHandler?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startStopButton.isEnabled = true
        predictionLabel.text = "Prediction: "
        confidenceLabel.text = "Confidence: "
        myTimer.text = "0"
//        var active:activity
        // We set this object as the sensor dispatch handler in order to receive
        // sensor data.
        //sensorDispatch.handler = self
        
        sensorDispatch.handler = self as? SensorDispatchHandler
        
        // Do any additional setup after loading the view.
        startStopButton.isEnabled = true

        startStopButton.setTitle("Start Recording", for: .normal)
        startStopButton.backgroundColor = .green
        
        
        motionManager.startAccelerometerUpdates()
        motionManager.startGyroUpdates()
        motionManager.startMagnetometerUpdates()

        //guard let fileURL = Bundle.main.url(forResource: "model_config_activity_recognition", withExtension: "yml") else {
        guard let fileURL = Bundle.main.url(forResource: "look_left_look_up_model_config", withExtension: "yml") else {
            fatalError("Sig Def YAML file not found in bundle. Please add and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let configuration = try! Yaml.load(contents)
            //print(configuration)
            print(configuration["num_results"])
            let num_results = configuration["num_results"].int!
            let modelInfo:FileInfo = (name:configuration["model_filename"].string!, extension:"")
            let labelInfo:FileInfo = (name:configuration["labels_filename"].string!, extension:"")
            modelDataHandler =
                ModelDataHandler(modelFileInfo: modelInfo, labelsFileInfo: labelInfo ,
                                 configuredResultCount: num_results)
            guard modelDataHandler != nil else {
                fatalError("Model set up failed")
            }
            num_values_per_sensor_dimenion = configuration["data_format"]["num_values_per_sensor_dimenion"].int!
            for index in 0..<configuration["data_format"]["sensor_dimension_ordering"].count! {
                let sensor_dim = configuration["data_format"]["sensor_dimension_ordering"][index].string!
                sensor_dimension_ordering.append(sensor_dim)
                normalization_value.append(configuration["data_format"]["normalization_value"][index].double!)
            }
            normalization_values_loaded = true
            model_sample_period = configuration["data_format"]["sample_period"].int!
        } catch {
            fatalError("Invalid Sig Def YAML file. Try again.")
        }
        
        accelChart.chartDescription?.text = "Accelerometer" // Here we set the description for the graph
        gyroChart.chartDescription?.text = "Gyroscope"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // If we are being pushed on to a navigation controller...
        if isMovingToParent {
            // Block this view controller's UI while the session is being opened
            activityIndicator = ActivityIndicator.add(to: navigationController?.view)
            
            // Register this view controller as the session delegate.
            session.delegate = self as? WearableDeviceSessionDelegate
            
            // Open the session.
            session.open()
            
            //wavFiletableview.dataSource = self
            //wavFiletableview.delegate = self
        }
    }
    
    // Error handler function called at various points in this class.  If an error
    // occurred, show it in an alert. When the alert is dismissed, this function
    // dismisses this view controller by popping to the root view controller (we are
    // assumed to be on a navigation stack).
    private func dismiss(dueTo error: Error?, isClosing: Bool = false) {
        // Common dismiss handler passed to show()/showAlert().
        let popToRoot = { [weak self] in
            DispatchQueue.main.async {
                self?.navigationController?.popToRootViewController(animated: true)
            }
        }
        
        // If the connection did close and it was not due to an error, just show
        // an appropriate message.
        if isClosing && error == nil {
            navigationController?.showAlert(title: "Disconnected", message: "The connection was closed", dismissHandler: popToRoot)
        }
            // Show an error alert.
        else {
            navigationController?.show(error, dismissHandler: popToRoot)
        }
    }
    
    private func listenForWearableDeviceEvents() {
        // Listen for incoming wearable device events. Retain the ListenerToken.
        // When the ListenerToken is deallocated, this object is automatically
        // removed as an event listener.
        token = session.device?.addEventListener(queue: .main) { [weak self] event in
            self?.wearableDeviceEvent(event)
        }
    }
    
    private func wearableDeviceEvent(_ event: WearableDeviceEvent) {
        // We are only interested in the event that the sensor configuration could
        // not be updated. In this case, show the error to the user. Otherwise,
        // ignore the event.
        guard case .didFailToWriteSensorConfiguration(let error) = event else {
            return
        }
        show(error)
    }
    
    private func listenForSensors() {
        // Configure sensors at 50 Hz (a 20 ms sample period)
        session.device?.configureSensors { config in
            
            // Here, config is the current sensor config. We begin by turning off
            // all sensors, allowing us to start with a "clean slate."
            config.disableAll()
            
            // Enable the rotation and accelerometer sensors
            //config.enable(sensor: .rotation, at: ._40ms)
            config.enable(sensor: .gyroscope, at: ._40ms)
            config.enable(sensor: .accelerometer, at: ._40ms)
        }
    }
    
    private func stopListeningForSensors() {
        // Disable all sensors.
        session.device?.configureSensors { config in
            config.disableAll()
        }
    }
    
    func delay(_ delay:Double, closure:@escaping ()->()){
        //function from stack overflow. Delay in seconds
        let when = DispatchTime.now() + delay
        DispatchQueue.main.asyncAfter(deadline: when, execute: closure)
        
    }
    //START STOP ACTIVITY
    @IBAction func startStop(_ sender: Any) {
            if(dataCollectionStaretd)
          {
            stopDataCollection()
                
        }
            else {
           //Setting a delay of 2.5 second before the recording will start. This is to ensure user is ready to start performing the activity.A beep sound will also sound once the recording starts or stops
                delay(2.5){
                    self.startDataCollection()
                }
            }
    }
//Counter for timer
    var counter: Int = 0
    var clock = Timer()
// Timer displya the counter value and increments by 1
     func startTimer()
     {
        clock = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(UpdateTimer), userInfo: nil, repeats: true)
       
    }
 //Stops the clock and resets the counter to 0
    func stopTimer()
    {
        
        clock.invalidate()
        counter = 0
    }
    //Update timer function
    @objc func UpdateTimer()
    {
        
        counter = counter + 1
        myTimer.text = String(counter)
        self.updateGraph()

        // perform inferencing every 4 seconds
        if counter % 4 == 0 {
            self.Result()
        }
       //after 60 secs, recording will stop automatically. Beep will sound.
        if counter == 60
        {
            dataCollectionStaretd = false
            startStopButton.setTitle("Start Recording Again", for: .normal)
            startStopButton.backgroundColor = .green
            AudioServicesPlaySystemSound(self.systemSoundID)
            stopTimer()
        }
        
    }
    
    //Normalization func. Currently not being used as model does not require normalization. (Data - Mean / Standard deviation)
    func normalize(str:[Double]) -> [Double]{
        var res:[Double] = []
        var mean: Double = 0.0
        vDSP_meanvD(str, 1, &mean, vDSP_Length(str.count))
        var msv:Double=0.0
        vDSP_measqvD(str, 1, &msv, vDSP_Length(str.count))
        let std = sqrt(msv - mean * mean) * sqrt(Double(str.count)/Double(str.count))
        for i in str {
            res.append((i-mean)/std)
        }
        return (res)
        
    }
    
    // Aayush: prediction algorithm
    //This is a recursive function that defines the prediction flow. X, Y and Z buffers get data continuously, but we only take the last 80 elements for the real time prediction. (Frames are caliberated at 25Hz, hence buffer takes 3.2 seconds to get filled up. (25 * 3.2 = 80). all axis data is stored in a single buffer with shape (1,240), which gets passed to mlMultiArray. Prediction happens with this data. After 4 seconds the function is self called for the second prediction.
    
    func Result() {

        var sensorDataBytes : [Float] = []
        self.active.mainData = []
        for index in 0..<sensor_dimension_ordering.count {
            self.active.mainData += returnSensorDimension(name:sensor_dimension_ordering[index]).suffix(num_values_per_sensor_dimenion)
        }

        for (_, element) in active.mainData.enumerated() {
            sensorDataBytes.append(Float(element))
        }
        // Pass the  buffered sensor data to TensorFlow Lite to perform inference.
        let result = modelDataHandler?.runModel(input: Data(buffer: UnsafeBufferPointer(start: sensorDataBytes, count: sensorDataBytes.count)))
       //Changing the text of the predictionLabel
        predictionLabel.text = result?.inferences[0].label//prediction?.classLabel
        confidenceLabel.text = String(describing : Int16((result?.inferences[0].confidence ?? 0.0) * 100.0)) + "%\n"
    }
    
    func returnSensorDimension(name:String)->[Double] {
        var array:[Double]=[]
        switch name {
        case "accel_x":
            array = self.active.accel.dataX
        case "accel_y":
            array = self.active.accel.dataY
        case "accel_z":
            array = self.active.accel.dataZ
        case "gyro_x":
            array = self.active.gyro.dataX
        case "gyro_y":
            array = self.active.gyro.dataY
        case "gyro_z":
            array = self.active.gyro.dataZ
        default:
            array = self.active.accel.dataX
        }
        return array
    }

    func returnSensorDimensionNormalizationValue(name:String)->Double {
        let index = sensor_dimension_ordering.lastIndex(of: name)
        if index != nil {
            return normalization_value[index!]
        } else {
            return 1.0
        }
    }
    
    @IBAction func emailData(_ sender: Any) {
        
        if( MFMailComposeViewController.canSendMail() ) {
            print("Can send email")
            
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self
            
            //Set the subject and message of the email
            mailComposer.setSubject("IMU Data")
            mailComposer.setMessageBody("Kindly find sample data in the attachment", isHTML: false)
            
            
            if let AccelData = NSData(contentsOf: fileURLAccel!) {
                print("Accel Data loaded.")
                
                mailComposer.addAttachmentData(AccelData as Data, mimeType: "text/txt", fileName: fileNameAccel)
            }
            
            if let GyroData = NSData(contentsOf: fileURLGyro!) {
                print("Gyro Data path loaded.")
                
                mailComposer.addAttachmentData(GyroData as Data, mimeType: "text/txt", fileName: fileNameGyro)
                
            }
            
            self.navigationController?.present(mailComposer, animated: true, completion: nil)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    //Empty the buffer if stop button gets called
    func stopResult()
    {
        self.active.mainData=[]
    }
    
    func setUpDataCollectionLogFiles()  {
        
        // Instead of getting file name from the text field, it needs to come from the options displayed. Once the user has clicked on an activity, example: Walking, the text 'walking' should be in the file name in place of fileNameTextField.text
        // Remove the FileName textbox and just use the label of the button clicked. 
        
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as NSURL
        let inputText = "Dummy"
        
        fileNameAccel = inputText + "_"  + "_Accel_" + fileStartRecordTimeStamp + ".csv"
        fileNameGyro  = inputText + "_" +  "_Gyro_" +  fileStartRecordTimeStamp + ".csv"
       //fileNameRoto  = activityLabel.text! + "_Roto_" +  fileStartRecordTimeStamp + ".csv"
        
        fileURLAccel = documentDirectory.appendingPathComponent(fileNameAccel)
        fileURLGyro = documentDirectory.appendingPathComponent(fileNameGyro)
        //fileURLRoto = documentDirectory.appendingPathComponent(fileNameRoto)
        
        firstWriteToAccelFile = true
        writeAccelDataCollectionFileHeader()
        
        firstWriteToGyroFile = true
        writeGyroDataCollectionFileHeader()
        
        firstWriteToRotoFile = true
       // writeRotoDataCollectionFileHeader()
    }
    
    func getCurrentTimeStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH-mm-ss-SSS, yyyy-MM-dd"
        
        let dataString:String =  formatter.string(from: Date())
        return dataString
    }
    
        // MARK: - table View
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wavFileNameList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")! //1.
        
        let text = wavFileNameList[indexPath.row] //2.
        
        cell.textLabel?.text = text //3.
        
        return cell //4.
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        print("Index Selected \(indexPath.row)")
        
        wavTableCellSelected = indexPath.row
    }
    
}

// MARK: - SensorDispatchHandler

// Note, we only have to implement the SensorDispatchHandler functions for the
// sensors we are interested in. These functions are called on the main queue
// as that is the queue provided to the SensorDispatch initializer.

extension DataCollectionViewController: SensorDispatchHandler {
    
    
    func receivedAccelerometer(vector: Vector, accuracy: VectorAccuracy, timestamp: SensorTimestamp) {
        var vector_local = vector
        if(dataCollectionStaretd)
        {
            var AccelData:String = ""
            AccelData += "\(String(describing: timestamp)), "
            AccelData += "\(String(describing: vector.x)), "
            AccelData += "\(String(describing: vector.y)), "
            AccelData += "\(String(describing: vector.z)),"
            if let accelerometerData = motionManager.accelerometerData {
                AccelData += "\(String(describing: accelerometerData.acceleration.x)), "
                AccelData += "\(String(describing: accelerometerData.acceleration.y)), "
                AccelData += "\(String(describing: accelerometerData.acceleration.z)) \n"
                writeToAccelFile(txt: AccelData)
            }
            
            // Normalize accelerometer values
            var normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_x")
            vector_local.x /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_y")
            vector_local.y /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_z")
            vector_local.z /= normalization_factor
            
            active.accel = appendSensorData(sensorData:active.accel, timeStamp:timestamp, vector:vector_local)

        }
    }
    func receivedGyroscope(vector: Vector, accuracy: VectorAccuracy, timestamp: SensorTimestamp)  {
        var vector_local = vector
        var unwrappedTimeStamp:Int64 = 0
        var timeStampDelta:Int = 0
        let millisecToSec = 0.001
        if(dataCollectionStaretd)
        {
            var GyroData:String = ""
            
            GyroData += "\(String(describing: timestamp)), "
            GyroData += "\(String(describing: vector.x)), "
            GyroData += "\(String(describing: vector.y)), "
            GyroData += "\(String(describing: vector.z)),"
            //GyroData += commentTxtField.text + "\n"
            
            if let gyroData = motionManager.gyroData {
                GyroData += "\(String(describing: gyroData.rotationRate.x)), "
                GyroData += "\(String(describing: gyroData.rotationRate.y)), "
                GyroData += "\(String(describing: gyroData.rotationRate.z)) \n"
                writeToGyroFile(txt: GyroData)
            }

            var normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_x")
            vector_local.x /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_y")
            vector_local.y /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_z")
            vector_local.z /= normalization_factor

            active.gyro = appendSensorData(sensorData:active.gyro, timeStamp:timestamp, vector:vector_local)
        }
    }
    
    func appendSensorData(sensorData:SensorData, timeStamp:SensorTimestamp, vector:Vector) -> SensorData {
        var unwrappedTimeStamp:Int64 = 0
        var timeStampDelta = 0
        let millisecToSec = 0.001
        var localSensorData = sensorData
        
        if localSensorData.prevDataTimeStamp == 0 &&
           localSensorData.maxDataTimeStamp == 0 {
           localSensorData.prevDataTimeStamp = timeStamp
        }
        if timeStamp < sensorData.prevDataTimeStamp {
            // Handle wraparounds
            active.accel.maxDataTimeStamp += Int64(65536)
            timeStampDelta = Int(round(Double(Int(timeStamp) + 65535 - Int(localSensorData.prevDataTimeStamp))/Double(model_sample_period)))
        }
        else {
            timeStampDelta = Int(round(Double(Int(timeStamp) - Int(localSensorData.prevDataTimeStamp))/Double(model_sample_period)))
        }
        if (timeStampDelta > 10) {
            stopDataCollection()
            startDataCollection()
        }
        else {
            for index in stride(from: 1, through: timeStampDelta-1, by: 1) {
                let timeStampBase = localSensorData.maxDataTimeStamp + Int64(localSensorData.prevDataTimeStamp)
                localSensorData.dataTimeStamp.append(Double(timeStampBase + Int64(index) * Int64(model_sample_period)) * millisecToSec)
                let scale = Double(index)/Double(timeStampDelta)
                let lastX : Double = localSensorData.dataX.last ?? 0.0
                let lastY : Double = localSensorData.dataY.last ?? 0.0
                let lastZ : Double = localSensorData.dataZ.last ?? 0.0
                localSensorData.dataX.append(lastX + scale * (vector.x - lastX))
                localSensorData.dataY.append(lastY + scale * (vector.y - lastY))
                localSensorData.dataZ.append(lastZ + scale * (vector.z - lastZ))
                localSensorData.interpolatedDataX.append(lastX + scale * (vector.x - lastX))
                localSensorData.interpolatedDataY.append(lastY + scale * (vector.y - lastY))
                localSensorData.interpolatedDataZ.append(lastZ + scale * (vector.z - lastZ))
            }
            unwrappedTimeStamp = Int64(timeStamp) + localSensorData.maxDataTimeStamp
            localSensorData.prevDataTimeStamp = timeStamp
            localSensorData.dataTimeStamp.append(Double(unwrappedTimeStamp) * millisecToSec)
            //Buffer stores x, y and z accelerometer data from frames.
            localSensorData.dataX.append(vector.x)
            localSensorData.dataY.append(vector.y)
            localSensorData.dataZ.append(vector.z)
            localSensorData.interpolatedDataX.append(0.0)
            localSensorData.interpolatedDataY.append(0.0)
            localSensorData.interpolatedDataZ.append(0.0)
            localSensorData.dataX = localSensorData.dataX.suffix(240)
            localSensorData.dataY = localSensorData.dataY.suffix(240)
            localSensorData.dataZ = localSensorData.dataZ.suffix(240)
            localSensorData.dataTimeStamp = localSensorData.dataTimeStamp.suffix(240)
            localSensorData.interpolatedDataX = localSensorData.interpolatedDataX.suffix(240)
            localSensorData.interpolatedDataY = localSensorData.interpolatedDataY.suffix(240)
            localSensorData.interpolatedDataZ = localSensorData.interpolatedDataZ.suffix(240)
        }
        return localSensorData
    }
    
    func writeGyroDataCollectionFileHeader()  {
        var gyroDataHeader:String = ""
        gyroDataHeader += "timeStamp (ms), "
        gyroDataHeader += "Bose Gyro X, "
        gyroDataHeader += "Bose Gyro Y, "
        gyroDataHeader += "Bose Gyro Z,"
        gyroDataHeader += "iPhone Gyro X,"
        gyroDataHeader += "iPhone Gyro Y,"
        gyroDataHeader += "iPhone Gyro Z \n"
        
        writeToGyroFile(txt: gyroDataHeader)
    }
    
    
    
    func writeAccelDataCollectionFileHeader()  {
        var AccelDataHeader:String = ""
        AccelDataHeader += "timeStamp (ms), "
        AccelDataHeader += "Bose Accel X, "
        AccelDataHeader += "Bose Accel Y, "
        AccelDataHeader += "Bose Accel Z,"
        AccelDataHeader += "iPhone Accel X, "
        AccelDataHeader += "iPhone Accel Y, "
        AccelDataHeader += "iPhone Accel Z \n"
        
        writeToAccelFile(txt: AccelDataHeader)
    }
    

    
    func writeToAccelFile(txt:String)  {
        
        let data = Data(txt.utf8)
        
        if(firstWriteToAccelFile)
        {
            firstWriteToAccelFile = false
            do {
                try data.write(to: fileURLAccel!, options: .atomic)
            } catch {
                print(error)
            }
        }
        else
        {
            
            do {
                let fileHandle = try FileHandle(forWritingTo: fileURLAccel!)
                fileHandle.seekToEndOfFile()
                fileHandle.write(txt.data(using: .utf8)!)
                fileHandle.closeFile()
            } catch {
                print("Error writing to file \(error)")
            }
        }
        
    }
    
    func writeToGyroFile(txt:String)  {
        
        let data = Data(txt.utf8)
        
        if(firstWriteToGyroFile)
        {
            firstWriteToGyroFile = false
            do {
                try data.write(to: fileURLGyro!, options: .atomic)
            } catch {
                print(error)
            }
        }
        else
        {
            
            do {
                let fileHandle = try FileHandle(forWritingTo: fileURLGyro!)
                fileHandle.seekToEndOfFile()
                fileHandle.write(txt.data(using: .utf8)!)
                fileHandle.closeFile()
            } catch {
                print("Error writing to file \(error)")
            }
        }
        
    }
    

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?){
        view.endEditing(true)
        super.touchesBegan(touches, with: event)
    }
    
    
}

// MARK: - WearableDeviceSessionDelegate

//This function looks for sensors in the device

extension DataCollectionViewController: WearableDeviceSessionDelegate {
    func sessionDidOpen(_ session: WearableDeviceSession) {
        // The session opened successfully.
        
        // Set the title to the device's name.
        title = session.device?.name
        
        // Listen for wearable device events.
        listenForWearableDeviceEvents()
        
        // Listen for sensor data.
        listenForSensors()
        
        // Unblock this view controller's UI.
        activityIndicator?.removeFromSuperview()
    }
    
    func session(_ session: WearableDeviceSession, didFailToOpenWithError error: Error?) {
        // The session failed to open due to an error.
        dismiss(dueTo: error)
        
        // Unblock this view controller's UI.
        activityIndicator?.removeFromSuperview()
    }
    
    func session(_ session: WearableDeviceSession, didCloseWithError error: Error?) {
        // The session was closed, possibly due to an error.
        dismiss(dueTo: error, isClosing: true)
        
        // Unblock this view controller's UI.
        activityIndicator?.removeFromSuperview()
    }
    
    func updateGraph(){
        
        accelChart = updateSensorGraph(chartName:accelChart, sensorData:active.accel)
        gyroChart = updateSensorGraph(chartName:gyroChart, sensorData:active.gyro)
    }

    func updateSensorGraph(chartName:LineChartView, sensorData:SensorData) -> LineChartView {
        let localChart = chartName
        let sensorLineChart = LineChartData() //This is the object that will be added to the chart
        let line1 : LineChartDataSet = addCurve(curveName : sensorData.dataX, timestamps : sensorData.dataTimeStamp, label : "Data-X", color : NSUIColor.blue)
        let line2 : LineChartDataSet = addCurve(curveName : sensorData.dataY, timestamps : sensorData.dataTimeStamp, label : "Data-Y", color : NSUIColor.red)
        let line3 : LineChartDataSet = addCurve(curveName : sensorData.dataZ, timestamps : sensorData.dataTimeStamp, label : "Data-Z", color : NSUIColor.green)
        let line4 : LineChartDataSet = addCurve(curveName : sensorData.interpolatedDataX, timestamps : sensorData.dataTimeStamp, label : "interpolatedData-X", color : NSUIColor.black)
        let line5 : LineChartDataSet = addCurve(curveName : sensorData.interpolatedDataY, timestamps : sensorData.dataTimeStamp, label : "interpolatedData-X", color : NSUIColor.cyan)
        let line6 : LineChartDataSet = addCurve(curveName : sensorData.interpolatedDataZ, timestamps : sensorData.dataTimeStamp, label : "interpolatedData-Z", color : NSUIColor.yellow)
        
        
        sensorLineChart.addDataSet(line1) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line2) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line3) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line4) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line5) //Adds the line to the dataSet
        sensorLineChart.addDataSet(line6) //Adds the line to the dataSet
        localChart.data = sensorLineChart //finally - it adds the chart data to the chart and causes an update

        return localChart
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
    
    func flushDataBuffers() {
        self.active.accel = flushSensorData(sensorData:self.active.accel)
        self.active.gyro = flushSensorData(sensorData:self.active.gyro)
    }
    
    func flushSensorData(sensorData:SensorData) -> SensorData {
        var localSensorData = sensorData
        localSensorData.dataX.removeAll()
        localSensorData.dataY.removeAll()
        localSensorData.dataZ.removeAll()
        localSensorData.dataTimeStamp.removeAll()
        localSensorData.prevDataTimeStamp = 0
        localSensorData.maxDataTimeStamp = 0
        localSensorData.interpolatedDataX.removeAll()
        localSensorData.interpolatedDataY.removeAll()
        localSensorData.interpolatedDataZ.removeAll()
        return localSensorData
    }
    func stopDataCollection() {
        dataCollectionStaretd = false
        startStopButton.setTitle("Start Recording", for: .normal)
        startStopButton.backgroundColor = .green
        stopTimer()
        stopResult()
        AudioServicesPlaySystemSound(self.systemSoundID)
    }
    
    func startDataCollection() {
        AudioServicesPlaySystemSound(self.systemSoundID)
        self.startStopButton.backgroundColor = .red
        self.startStopButton.setTitle("Stop Recording", for: .normal)
        self.fileStartRecordTimeStamp = self.getCurrentTimeStamp()
        self.setUpDataCollectionLogFiles()
        self.dataCollectionStaretd = true
        self.flushDataBuffers()
        self.startTimer()
    }
}
