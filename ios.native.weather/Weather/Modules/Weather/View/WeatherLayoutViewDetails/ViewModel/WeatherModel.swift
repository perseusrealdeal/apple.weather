//
//  WeatherModel.swift
//  Weather
//
//  Created by Mikhail Zhigulin on 24.12.2021.
//

import Foundation
import SwiftyJSON

fileprivate let WEATHER_CURRENT_LOCATION_KEY = "weather_forecast_for_current_location"

class WeatherDataModel
{
    // MARK: - Business Matter Data
    
    var alerts             : [NationalAlert]? { parser() }
    
    var forecastHourly     : [ForecastHour]? { parser() }
    var forecastDaily      : [ForecastDay]? { parser() }
    var currentWeather     : CurrentWeather? { parser() }
    
    private var jsonData   : JSON!
    
    // MARK: - Init
    
    init()
    {
        #if DEBUG
        print(">> [\(type(of: self))]." + #function)
        #endif
        
        jsonData = loadData()
        
        #if DEBUG
        print("loaded       : \(target == nil ? "nothing" : target!.location.description)")
        #endif
        
        #if DEBUG
        let time = jsonData["lastFullUpdate"].doubleValue
        print("fullUpdate   : \(Date(timeIntervalSince1970: time))")
        #endif
    }
    
    // MARK: - Service Matter Data
    
    var target                     : CurrentLocationDescription? { parser() }
    
    var lastFullUpdateTime         : LastFullUpdateTime? { parser() }
    
    var isForecastHourlyUpToDate   : Bool
    {
        guard let timeToUpdate = forecastHourly?[1].dt else { return false }
        
        let timeNow = Date().timeIntervalSince1970
        let result = timeNow < timeToUpdate
        
        return result
    }
    
    var isForecastDailyUpToDate    : Bool
    {
        if let today = forecastDaily?.first?.dt
        {
            return isDayUpToDate(from: today)
        }
        
        return false
    }
    
    var isForecastCurrentUpToDate  : Bool
    {
        if let today = currentWeather?.dt
        {
            return isDayUpToDate(from: today)
        }
        
        return false
    }
    
    // MARK: - Business matter operations
    
    func update(received data: Data, _ completed:((_ onlyAlerts: Bool) -> Void))
    {
        #if DEBUG
        print(">> [\(type(of: self))]." + #function)
        #endif
        
        guard let json = try? JSON(data: data) else { return }
        
        var weatherDataChanged = false
        var fullUpdated = true
        
        var weatherDataCountChanges = 0
        var alertsChanged = false
        
        if json["current"].exists()
        {
            weatherDataChanged = true
            weatherDataCountChanges = weatherDataCountChanges + 1
            
            jsonData["current"] = json["current"]
        }
        else { fullUpdated = false; print("current not exists") }
        
        if json["hourly"].exists()
        {
            weatherDataChanged = true
            weatherDataCountChanges = weatherDataCountChanges + 1
            
            jsonData["hourly"] = json["hourly"]
        }
        else { fullUpdated = false; print("hourly not exists") }
        
        if json["daily"].exists()
        {
            weatherDataChanged = true
            weatherDataCountChanges = weatherDataCountChanges + 1
            
            jsonData["daily"] = json["daily"]
        }
        else { fullUpdated = false; print("daily not exists") }
        
        if json["alerts"].exists()
        {
            weatherDataChanged = true
            alertsChanged = true
            
            jsonData["alerts"] = json["alerts"]
        }
        else
        {
            if !jsonData["alerts"].isEmpty
            {
                weatherDataChanged = true
                alertsChanged = true
                
                jsonData["alerts"] = JSON()
                
                #if DEBUG
                print("alerts erased")
                #endif
                
            }
            
            #if DEBUG
            print("alerts not exists")
            #endif
        }
        
        if fullUpdated
        {
            jsonData["lastFullUpdate"].double = Date().timeIntervalSince1970
            
            #if DEBUG
            let saved = Date(timeIntervalSince1970: jsonData["lastFullUpdate"].doubleValue)
            print("fullUpdate   : \(saved)")
            #endif
        }
        
        if weatherDataChanged
        {
            self.jsonData["lat"] = json["lat"]
            self.jsonData["lon"] = json["lon"]
            self.jsonData["timezone"] = json["timezone"]
            self.jsonData["timezone_offset"] = json["timezone_offset"]
            
            saveData()
            
            let onlyAlerts = ((weatherDataCountChanges == 0) && alertsChanged) ? true : false
            
            completed(onlyAlerts)
        }
        
    }
    
    // MARK: - Service matter operations
    
    private func loadData() -> JSON
    {
        #if DEBUG
        print(">> [\(type(of: self))]." + #function)
        #endif
        
        guard
            Settings.userDefaults.valueExists(forKey: WEATHER_CURRENT_LOCATION_KEY),
            let object = Settings.userDefaults.object(forKey: WEATHER_CURRENT_LOCATION_KEY),
            let result = JSON(rawValue: object)
        else { return JSON() }
        
        return result
    }
    
    private func saveData()
    {
        #if DEBUG
        print(">> [\(type(of: self))]." + #function)
        #endif
        
        guard let json = jsonData, !json.isEmpty, json["current"].exists() else { return }
        
        Settings.userDefaults.setValue(json.rawValue, forKey: WEATHER_CURRENT_LOCATION_KEY)
        
        #if DEBUG
        print("saved        : \(target == nil ? "nothing" : target!.location.description)")
        #endif
    }
    
    // MARK: - Other calculations
    
    private func isDayUpToDate(from: Double) -> Bool
    {
        guard let offset = target?.timezone_offset else { return false }
        
        let timeOfDay = Date(timeIntervalSince1970: from).addingTimeInterval(offset)
        
        let startOfDay =  Calendar.current.startOfDay(for: timeOfDay).addingTimeInterval(offset)
        
        let components = DateComponents(hour: 23, minute: 59, second: 59)
        let endOfDay = Calendar.current.date(byAdding: components, to: startOfDay)!
        
        let timeNow = Date().addingTimeInterval(offset)
        
        return timeNow < endOfDay
    }
}

extension WeatherDataModel
{
    private func parser() -> CurrentLocationDescription?
    {
        guard
            let json = self.jsonData, !json.isEmpty, json["lat"].exists(),
            json["lon"].exists(), json["timezone_offset"].exists()
        else { return nil }
        
        return CurrentLocationDescription(latitude        : json["lat"].doubleValue,
                                          longitude       : json["lon"].doubleValue,
                                          timezone_offset : json["timezone_offset"].doubleValue)
    }
    
    private func parser() -> LastFullUpdateTime?
    {
        guard
            let json = self.jsonData, !json.isEmpty,
            json["lastFullUpdate"].exists()
        else { return nil }
        
        return LastFullUpdateTime(dt: json["lastFullUpdate"].doubleValue)
    }
    
    private func parser() -> CurrentWeather?
    {
        guard
            let json = self.jsonData, !json.isEmpty,
            json["current"].exists(), json["current"]["dt"].exists()
        else { return nil }
        
        return CurrentWeather(dt: json["current"]["dt"].doubleValue)
    }
    
    private func parser() -> [ForecastHour]?
    {
        guard
            let json = self.jsonData, !json.isEmpty,
            json["hourly"].exists(), !json["hourly"].isEmpty
        else { return nil }
        
        var result : [ForecastHour] = []
        
        for (_,subJson):(String, JSON) in jsonData["hourly"]
        {
            let item = ForecastHour(dt: subJson["dt"].doubleValue)
            
            result.append(item)
        }
        
        return result
    }
    
    private func parser() -> [ForecastDay]?
    {
        guard
            let json = self.jsonData, !json.isEmpty,
            json["daily"].exists(), !json["daily"].isEmpty
        else { return nil }
        
        var result : [ForecastDay] = []
        
        for (_,subJson):(String, JSON) in jsonData["daily"]
        {
            let item = ForecastDay(dt: subJson["dt"].doubleValue)
            
            result.append(item)
        }
        
        return result
    }
    
    private func parser() -> [NationalAlert]?
    {
        return nil
    }
}



extension WeatherDataModel
{
    private func printAlerts()
    {
        #if DEBUG
        print("alerts       : begin")
        #endif
        
        for (index,subJson):(String, JSON) in jsonData["alerts"]
        {
            print("index        : \(index)")
            print("name         : \(subJson["event"])")
            
            let timeStart = Date(timeIntervalSince1970: subJson["start"].doubleValue)
            let timeEnd = Date(timeIntervalSince1970: subJson["end"].doubleValue)
            
            print("start time   : \(timeStart)")
            print("end time     : \(timeEnd)")
        }
        
        #if DEBUG
        print("alerts       : end")
        #endif
    }
    
    func printHourly()
    {
        #if DEBUG
        print("hourly       : begin")
        #endif
        
        print("time now     : \(Date())")
        
        for (index,subJson):(String, JSON) in jsonData["hourly"]
        {
            print("index        : \(index)")
            
            let time = Date(timeIntervalSince1970: subJson["dt"].doubleValue)
            
            print("time         : \(time)")
        }
        
        #if DEBUG
        print("hourly       : end")
        #endif
    }
}
