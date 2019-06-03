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
    
    @IBOutlet weak var chtChart: LineChartView!
    //Get the beep sound
    @IBOutlet weak var gyroChart: LineChartView!
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

        guard let fileURL = Bundle.main.url(forResource: "sig_def", withExtension: "yml") else {
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
            config.enable(sensor: .gyroscope, at: ._80ms)
            config.enable(sensor: .accelerometer, at: ._80ms)
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

        var accelBytes : [Float] = []
        self.active.mainData = []
        for index in 0..<sensor_dimension_ordering.count {
            self.active.mainData += returnSensorDimension(name:sensor_dimension_ordering[index]).suffix(num_values_per_sensor_dimenion)
        }

        for (_, element) in active.mainData.enumerated() {
            accelBytes.append(Float(element))
        }
        // Pass the  buffered sensor data to TensorFlow Lite to perform inference.
        let result = modelDataHandler?.runModel(input: Data(buffer: UnsafeBufferPointer(start: accelBytes, count: accelBytes.count)))
       //Changing the text of the predictionLabel
        predictionLabel.text = result?.inferences[0].label//prediction?.classLabel
        confidenceLabel.text = String(describing : Int16((result?.inferences[0].confidence ?? 0.0) * 100.0)) + "%\n"
    }
    
    func returnSensorDimension(name:String)->[Double] {
        var array:[Double]=[]
        switch name {
        case "accel_x":
            array = self.active.accelX
        case "accel_y":
            array = self.active.accelY
        case "accel_z":
            array = self.active.accelZ
        default:
            array = self.active.accelX
        }
        return array
    }

    func returnSensorDimensionNormalizationValue(name:String)->Double {
        let index = sensor_dimension_ordering.lastIndex(of: name)
        return normalization_value[index!]
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
    let millisecToSec = 0.001
    if(dataCollectionStaretd)
        {
            
            var AccelData:String = ""
            var unwrappedTimeStamp:Int64 = 0
            var timeStampDelta = 0
            AccelData += "\(String(describing: timestamp)), "
            AccelData += "\(String(describing: vector.x)), "
            AccelData += "\(String(describing: vector.y)), "
            AccelData += "\(String(describing: vector.z)),"
            if let accelerometerData = motionManager.accelerometerData {
                AccelData += "\(String(describing: accelerometerData.acceleration.x)), "
                AccelData += "\(String(describing: accelerometerData.acceleration.y)), "
                AccelData += "\(String(describing: accelerometerData.acceleration.z)) \n"
            }
            
            // Normalize accelerometer values
            if normalization_values_loaded == true {
                var normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_x")
                vector_local.x /= normalization_factor
                normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_y")
                vector_local.y /= normalization_factor
                normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_z")
                vector_local.z /= normalization_factor
            }
            if active.prevAccelSensorTimeStamp == 0 &&
                active.maxAccelSensorTimeStamp == 0 {
                active.prevAccelSensorTimeStamp = timestamp
            }
            if timestamp < active.prevAccelSensorTimeStamp {
                // Handle wraparounds
                active.maxAccelSensorTimeStamp += Int64(65536)
                timeStampDelta = Int(round(Double(Int(timestamp) + 65535 - Int(active.prevAccelSensorTimeStamp))/Double(model_sample_period)))
            }
            else {
                timeStampDelta = Int(round(Double(Int(timestamp) - Int(active.prevAccelSensorTimeStamp))/Double(model_sample_period)))
            }
            if (timeStampDelta > 4) {
                stopDataCollection()
                startDataCollection()
            }
            else {
                for index in stride(from: 1, through: timeStampDelta-1, by: 1) {
                    let timeStampBase = active.maxAccelSensorTimeStamp + Int64(active.prevAccelSensorTimeStamp)
                    active.accelTimeStamp.append(Double(timeStampBase + Int64(index) * Int64(model_sample_period)) * millisecToSec)
                    let scale = Double(index)/Double(timeStampDelta)
                    let lastX : Double = active.accelX.last ?? 0.0
                    let lastY : Double = active.accelY.last ?? 0.0
                    let lastZ : Double = active.accelZ.last ?? 0.0
                    active.accelX.append(lastX + scale * (vector_local.x - lastX))
                    active.accelY.append(lastY + scale * (vector_local.y - lastY))
                    active.accelZ.append(lastZ + scale * (vector_local.z - lastZ))
                    active.interpolatedAccelX.append(lastX + scale * (vector_local.x - lastX))
                    active.interpolatedAccelY.append(lastY + scale * (vector_local.y - lastY))
                    active.interpolatedAccelZ.append(lastZ + scale * (vector_local.z - lastZ))
                }
                unwrappedTimeStamp = Int64(timestamp) + active.maxAccelSensorTimeStamp
                active.prevAccelSensorTimeStamp = timestamp
                active.accelTimeStamp.append(Double(unwrappedTimeStamp) * millisecToSec)
                //Buffer stores x, y and z accelerometer data from frames.
                active.accelX.append(vector_local.x)
                active.accelY.append(vector_local.y)
                active.accelZ.append(vector_local.z)
                active.interpolatedAccelX.append(0.0)
                active.interpolatedAccelY.append(0.0)
                active.interpolatedAccelZ.append(0.0)
                active.accelX = active.accelX.suffix(240)
                active.accelY = active.accelY.suffix(240)
                active.accelZ = active.accelZ.suffix(240)
                active.accelTimeStamp = active.accelTimeStamp.suffix(240)
                active.interpolatedAccelX = active.interpolatedAccelX.suffix(240)
                active.interpolatedAccelY = active.interpolatedAccelY.suffix(240)
                active.interpolatedAccelZ = active.interpolatedAccelZ.suffix(240)
                writeToAccelFile(txt: AccelData)
            }
        }
    }
    func receivedGyroscope(vector: Vector, accuracy: VectorAccuracy, timestamp: SensorTimestamp)  {
        
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
            }

            if active.prevGyroSensorTimeStamp == 0 &&
                active.maxGyroSensorTimeStamp == 0 {
                active.prevGyroSensorTimeStamp = timestamp
            }
            if timestamp < active.prevGyroSensorTimeStamp {
                // Handle wraparounds
                active.maxGyroSensorTimeStamp += Int64(65536)
                timeStampDelta = Int(round(Double(Int(timestamp) + 65535 - Int(active.prevGyroSensorTimeStamp))/Double(model_sample_period)))
            }
            else {
                timeStampDelta = Int(round(Double(Int(timestamp) - Int(active.prevGyroSensorTimeStamp))/Double(model_sample_period)))
            }
            if (timeStampDelta > 4) {
                stopDataCollection()
                startDataCollection()
            }
            else {
                for index in stride(from: 1, through: timeStampDelta-1, by: 1) {
                    let timeStampBase = active.maxGyroSensorTimeStamp + Int64(active.prevGyroSensorTimeStamp)
                    active.gyroTimeStamp.append(Double(timeStampBase + Int64(index) * Int64(model_sample_period)) * millisecToSec)
                    let scale = Double(index)/Double(timeStampDelta)
                    let lastX : Double = active.gyroX.last ?? 0.0
                    let lastY : Double = active.gyroY.last ?? 0.0
                    let lastZ : Double = active.gyroZ.last ?? 0.0
                    active.gyroX.append(lastX + scale * (vector.x - lastX))
                    active.gyroY.append(lastY + scale * (vector.y - lastY))
                    active.gyroZ.append(lastZ + scale * (vector.z - lastZ))
                    active.interpolatedGyroX.append(lastX + scale * (vector.x - lastX))
                    active.interpolatedGyroY.append(lastY + scale * (vector.y - lastY))
                    active.interpolatedGyroZ.append(lastZ + scale * (vector.z - lastZ))
                }
                active.prevGyroSensorTimeStamp = timestamp
                unwrappedTimeStamp = Int64(timestamp) + active.maxGyroSensorTimeStamp
                active.gyroTimeStamp.append(Double(unwrappedTimeStamp) * millisecToSec)
                //Buffer stores x, y and z accelerometer data from frames.
                active.gyroX.append(vector.x)
                active.gyroY.append(vector.y)
                active.gyroZ.append(vector.z)
                active.interpolatedGyroX.append(0.0)
                active.interpolatedGyroY.append(0.0)
                active.interpolatedGyroZ.append(0.0)
                active.gyroX = Array(active.gyroX.suffix(240))
                active.gyroY = Array(active.gyroY.suffix(240))
                active.gyroZ = Array(active.gyroZ.suffix(240))
                active.interpolatedGyroX = active.interpolatedGyroX.suffix(240)
                active.interpolatedGyroY = active.interpolatedGyroX.suffix(240)
                active.interpolatedGyroZ = active.interpolatedGyroZ.suffix(240)
                active.gyroTimeStamp = Array(active.gyroTimeStamp.suffix(240))
                writeToGyroFile(txt: GyroData)
            }
        }
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
        chtChart.chartDescription?.text = "Accelerometer" // Here we set the description for the graph
        gyroChart.chartDescription?.text = "Gyroscope"
        let Acceldata = LineChartData() //This is the object that will be added to the chart
        let Gyrodata = LineChartData() //This is the object that will be added to the chart
        let line1 : LineChartDataSet = addCurve(curveName : active.accelX, timestamps : active.accelTimeStamp, label : "accelX", color : NSUIColor.blue)
        let line2 : LineChartDataSet = addCurve(curveName : active.accelY, timestamps : active.accelTimeStamp, label : "accelY", color : NSUIColor.red)
        let line3 : LineChartDataSet = addCurve(curveName : active.accelZ, timestamps : active.accelTimeStamp, label : "accelZ", color : NSUIColor.green)
        let line4 : LineChartDataSet = addCurve(curveName : active.gyroX, timestamps : active.gyroTimeStamp, label : "gyroX", color : NSUIColor.blue)
        let line5 : LineChartDataSet = addCurve(curveName : active.gyroY, timestamps : active.gyroTimeStamp, label : "gyroY", color : NSUIColor.red)
        let line6 : LineChartDataSet = addCurve(curveName : active.gyroZ, timestamps : active.gyroTimeStamp, label : "gyroZ", color : NSUIColor.green)
        let line7 : LineChartDataSet = addCurve(curveName : active.interpolatedAccelX, timestamps : active.accelTimeStamp, label : "interpolatedAccelX", color : NSUIColor.black)
        let line8 : LineChartDataSet = addCurve(curveName : active.interpolatedAccelY, timestamps : active.accelTimeStamp, label : "interpolatedAccelY", color : NSUIColor.cyan)
        let line9 : LineChartDataSet = addCurve(curveName : active.interpolatedAccelZ, timestamps : active.accelTimeStamp, label : "interpolatedAccelZ", color : NSUIColor.yellow)
        let line10 : LineChartDataSet = addCurve(curveName : active.interpolatedGyroX, timestamps : active.gyroTimeStamp, label : "interpolatedGyroX", color : NSUIColor.black)
        let line11 : LineChartDataSet = addCurve(curveName : active.interpolatedGyroY, timestamps : active.gyroTimeStamp, label : "interpolatedGyroY", color : NSUIColor.cyan)
        let line12 : LineChartDataSet = addCurve(curveName : active.interpolatedGyroZ, timestamps : active.gyroTimeStamp, label : "interpolatedGyroZ", color : NSUIColor.yellow)


        Acceldata.addDataSet(line1) //Adds the line to the dataSet
        Acceldata.addDataSet(line2) //Adds the line to the dataSet
        Acceldata.addDataSet(line3) //Adds the line to the dataSet
        Acceldata.addDataSet(line7) //Adds the line to the dataSet
        Acceldata.addDataSet(line8) //Adds the line to the dataSet
        Acceldata.addDataSet(line9) //Adds the line to the dataSet
        chtChart.data = Acceldata //finally - it adds the chart data to the chart and causes an update
        Gyrodata.addDataSet(line4) //Adds the line to the dataSet
        Gyrodata.addDataSet(line5) //Adds the line to the dataSet
        Gyrodata.addDataSet(line6) //Adds the line to the dataSet
        Gyrodata.addDataSet(line10) //Adds the line to the dataSet
        Gyrodata.addDataSet(line11) //Adds the line to the dataSet
        Gyrodata.addDataSet(line12) //Adds the line to the dataSet
        gyroChart.data = Gyrodata //finally - it adds the chart data to the chart and causes an update

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
        self.active.accelX.removeAll()
        self.active.accelY.removeAll()
        self.active.accelZ.removeAll()
        self.active.accelTimeStamp.removeAll()
        self.active.gyroX.removeAll()
        self.active.gyroY.removeAll()
        self.active.gyroZ.removeAll()
        self.active.gyroTimeStamp.removeAll()
        self.active.prevAccelSensorTimeStamp = 0
        self.active.prevGyroSensorTimeStamp = 0
        self.active.maxAccelSensorTimeStamp = 0
        self.active.maxGyroSensorTimeStamp = 0
        self.active.interpolatedAccelX.removeAll()
        self.active.interpolatedAccelY.removeAll()
        self.active.interpolatedAccelZ.removeAll()
        self.active.interpolatedGyroX.removeAll()
        self.active.interpolatedGyroY.removeAll()
        self.active.interpolatedGyroZ.removeAll()
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
