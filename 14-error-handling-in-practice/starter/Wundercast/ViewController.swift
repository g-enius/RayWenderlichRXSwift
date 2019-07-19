/*
 * Copyright (c) 2014-2016 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import RxSwift
import RxCocoa
import MapKit
import CoreLocation

typealias Weather = ApiController.Weather

var cachedData = [String: Weather]()

class ViewController: UIViewController {

  @IBOutlet weak var keyButton: UIButton!
  @IBOutlet weak var geoLocationButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var searchCityName: UITextField!
  @IBOutlet weak var tempLabel: UILabel!
  @IBOutlet weak var humidityLabel: UILabel!
  @IBOutlet weak var iconLabel: UILabel!
  @IBOutlet weak var cityNameLabel: UILabel!

  let bag = DisposeBag()

  let locationManager = CLLocationManager()

  var keyTextField: UITextField?
  
  var cache = [String: Weather]()

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    
    style()

    _ = RxReachability.shared.startMonitor("openweathermap.org")
    
    keyButton.rx.tap.subscribe(onNext: {
      self.requestKey()
    }).disposed(by:bag)

    let currentLocation = locationManager.rx.didUpdateLocations
      .map() { locations in
        return locations[0]
      }
      .filter() { location in
        return location.horizontalAccuracy < kCLLocationAccuracyHundredMeters
    }

    let geoInput = geoLocationButton.rx.tap.asObservable().do(onNext: {
      self.locationManager.requestWhenInUseAuthorization()
      self.locationManager.startUpdatingLocation()

      self.searchCityName.text = "Current Location"
    })

    let geoLocation = geoInput.flatMap {
      return currentLocation.take(1)
    }

    let geoSearch = geoLocation.flatMap() { location in
      return ApiController.shared.currentWeather(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        .catchErrorJustReturn(ApiController.Weather.empty)
    }
    
    let maxAttempts = 4
    
    let retryHandler: (Observable<Error>) -> Observable<Int> = { e in
      return e.enumerated().flatMap({ (attempt,error) -> Observable<Int> in
        if (error as NSError).code == -1009 {
          return RxReachability.shared.status
            .debug("+++ RxReachability.shared.status")
            .filter({ $0 == .online })
            .map({ _ in
                return 1
            })
        }
        else if attempt >= maxAttempts - 1 {
          return Observable.error(error)
        }
        else if let casted = error as? ApiController.ApiError, casted == .invalidKey {
          return ApiController.shared.apiKey
            .debug("+++ ApiController.shared.apiKey")
            .filter({ $0 != ""})
            .map({ _ in
                return 1
            })
        }
        print("== retrying after \(attempt + 1) seconds ==")
        
        //delay a mount of secondes and then emit only two events: OnNext(0), OnCompleted
        return Observable<Int>.timer(DispatchTimeInterval.seconds(attempt + 1), scheduler: MainScheduler.instance)
          .take(1)
      })
    }

    let searchInput = searchCityName.rx.controlEvent(.editingDidEndOnExit).asObservable()
      .map { self.searchCityName.text }
      .filter { ($0 ?? "").count > 0 }
    
    let textSearch = searchInput.flatMap { text in
      return ApiController.shared.currentWeather(city: text ?? "Error")
        .cacheOrShowError(key: text ?? "", displayErrorIn: self)
        .retryWhen(retryHandler)
        .catchError { error in
          if let text = text, let cachedData = cachedData[text] {
            return Observable.just(cachedData)
          } else {
            return Observable.just(ApiController.Weather.empty)
          }
        }
    }

    let search = Observable.from([geoSearch, textSearch])
      .merge()
      .asDriver(onErrorJustReturn: ApiController.Weather.empty)

    let running = Observable.from([searchInput.map { _ in true },
                                   geoInput.map { _ in true },
                                   search.map { _ in false }.asObservable()])
      .merge()
      .startWith(true)
      .asDriver(onErrorJustReturn: false)

    search.map { "\($0.temperature)° C" }
      .drive(tempLabel.rx.text)
      .disposed(by:bag)

    search.map { $0.icon }
      .drive(iconLabel.rx.text)
      .disposed(by:bag)

    search.map { "\($0.humidity)%" }
      .drive(humidityLabel.rx.text)
      .disposed(by:bag)

    search.map { $0.cityName }
      .drive(cityNameLabel.rx.text)
      .disposed(by:bag)

    running.skip(1).drive(activityIndicator.rx.isAnimating).disposed(by:bag)
    running.drive(tempLabel.rx.isHidden).disposed(by:bag)
    running.drive(iconLabel.rx.isHidden).disposed(by:bag)
    running.drive(humidityLabel.rx.isHidden).disposed(by:bag)
    running.drive(cityNameLabel.rx.isHidden).disposed(by:bag)

  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    Appearance.applyBottomLine(to: searchCityName)
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }

  func requestKey() {

    func configurationTextField(textField: UITextField) {
      self.keyTextField = textField
      self.keyTextField?.text = "62383c0f58aee05199188f60d73e457a"
    }

    let alert = UIAlertController(title: "Api Key",
                                  message: "Add the api key:",
                                  preferredStyle: UIAlertController.Style.alert)

    alert.addTextField(configurationHandler: configurationTextField)

    alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler:{ (UIAlertAction) in
      ApiController.shared.apiKey.onNext(self.keyTextField?.text ?? "")
    }))

    alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.destructive))

    self.present(alert, animated: true)
  }


  // MARK: - Style

  private func style() {
    view.backgroundColor = UIColor.aztec
    searchCityName.textColor = UIColor.ufoGreen
    tempLabel.textColor = UIColor.cream
    humidityLabel.textColor = UIColor.cream
    iconLabel.textColor = UIColor.cream
    cityNameLabel.textColor = UIColor.cream
  }
}


extension ObservableType where Element == Weather {
    
    /// Custom cache operator
    
    func cacheOrShowError(key: String, displayErrorIn viewController: UIViewController) -> Observable<Element> {
        return self.observeOn(MainScheduler.instance)
            .do(onNext: { data in
                cachedData[key] = data
            }, onError: { e in
                if let e = e as? ApiController.ApiError {
                    switch (e) {
                        case .cityNotFound:
                            InfoView.showIn(viewController: viewController, message: "City Name is invalid")
                        case .serverFailure:
                            InfoView.showIn(viewController: viewController, message: "Server error")
                        case .invalidKey:
                            InfoView.showIn(viewController: viewController, message: "Key is invalid")
                    }
                } else {
                    InfoView.showIn(viewController: viewController, message: "An error occurred")
                }
        })
    }
    
}
