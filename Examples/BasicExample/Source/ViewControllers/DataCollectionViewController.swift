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
import Accelerate
import CoreImage
import Charts

class DataCollectionViewController: UIViewController, MFMailComposeViewControllerDelegate {
    
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
    
    var dataCollectionStaretd:Bool = false
    
    var wavFileNameList = [String]()
    var wavTableCellSelected:Int?

    let motionManager = CMMotionManager()
        
    // Handles all data preprocessing and makes calls to run inference through TfliteWrapper
    private var modelDataHandler: ModelDataHandler?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startStopButton.isEnabled = true
        predictionLabel.text = "Prediction: "
        confidenceLabel.text = "Confidence: "
        myTimer.text = "0"
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
            modelDataHandler =
                ModelDataHandler(configFileName: "look_left_look_up_model_config.yml")
            guard modelDataHandler != nil else {
                fatalError("Model set up failed")
            }
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
        let (lineChart1, lineChart2) =  self.active.updateGraph()
        accelChart.data = lineChart1
        gyroChart.data = lineChart2
        
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
        self.active.aggregatedData = []
        for index in 0..<modelDataHandler!.sensor_dimension_ordering.count {
            self.active.aggregatedData += self.active.returnSensorDimension(name:modelDataHandler!.sensor_dimension_ordering[index]).suffix(modelDataHandler!.num_values_per_sensor_dimenion)
        }

        for (_, element) in active.aggregatedData.enumerated() {
            sensorDataBytes.append(Float(element))
        }
        // Pass the  buffered sensor data to TensorFlow Lite to perform inference.
        let result = modelDataHandler?.runModel(input: Data(buffer: UnsafeBufferPointer(start: sensorDataBytes, count: sensorDataBytes.count)))
       //Changing the text of the predictionLabel
        predictionLabel.text = result?.inferences[0].label//prediction?.classLabel
        confidenceLabel.text = String(describing : Int16((result?.inferences[0].confidence ?? 0.0) * 100.0)) + "%\n"
    }

    func returnSensorDimensionNormalizationValue(name:String)->Double {
        let index = modelDataHandler!.sensor_dimension_ordering.lastIndex(of: name)
        if index != nil {
            return modelDataHandler!.normalization_value[index!]
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
            
            
            if let AccelData = NSData(contentsOf: self.active.accel.logFileURL!) {
                print("Accel Data loaded.")
                
                mailComposer.addAttachmentData(AccelData as Data, mimeType: "text/txt", fileName: self.active.accel.logFileName)
            }
            
            if let GyroData = NSData(contentsOf: self.active.gyro.logFileURL!) {
                print("Gyro Data path loaded.")
                
                mailComposer.addAttachmentData(GyroData as Data, mimeType: "text/txt", fileName: self.active.gyro.logFileName)
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
        self.active.aggregatedData=[]
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
    
    
    /*func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
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
    }*/
    
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
                active.accel.writeToLogFile(txt: AccelData)
            }
            
            // Normalize accelerometer values
            var normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_x")
            vector_local.x /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_y")
            vector_local.y /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "accel_z")
            vector_local.z /= normalization_factor
            
            active.accel.appendSensorData(timeStamp:timestamp, vector:vector_local, model_sample_period: modelDataHandler!.model_sample_period)

        }
    }
    func receivedGyroscope(vector: Vector, accuracy: VectorAccuracy, timestamp: SensorTimestamp)  {
        var vector_local = vector
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
                active.gyro.writeToLogFile(txt: GyroData)
            }

            var normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_x")
            vector_local.x /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_y")
            vector_local.y /= normalization_factor
            normalization_factor = returnSensorDimensionNormalizationValue(name: "gyro_z")
            vector_local.z /= normalization_factor

            active.gyro.appendSensorData(timeStamp:timestamp, vector:vector_local, model_sample_period: modelDataHandler!.model_sample_period)
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
        self.dataCollectionStaretd = true
        self.active.flushDataBuffers()
        self.startTimer()
    }
}
