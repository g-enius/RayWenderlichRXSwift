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

class ViewController: UIViewController {

  @IBOutlet weak var mapView: MKMapView!
  @IBOutlet weak var mapButton: UIButton!
  @IBOutlet weak var geoLocationButton: UIButton!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var searchCityName: UITextField!
  @IBOutlet weak var tempLabel: UILabel!
  @IBOutlet weak var humidityLabel: UILabel!
  @IBOutlet weak var iconLabel: UILabel!
  @IBOutlet weak var cityNameLabel: UILabel!

  let bag = DisposeBag()
  
  let locationManager = CLLocationManager()

  override func viewDidLoad() {
    super.viewDidLoad()
    
    let currentLocation = locationManager.rx.didUpdateLocations
        .debug("currentLocation")
      .map { (locations) in
        return locations[0]
      }
      .filter { (location) in
        return location.horizontalAccuracy < kCLLocationAccuracyHundredMeters
      }
    
    let geoInput = geoLocationButton.rx.tap.asObservable()
        .debug("geoInput")
      .do(onNext: {
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
      })
        .share(replay: 1, scope: .forever)
    
    let geoLocation = geoInput.flatMap {
      return currentLocation.take(1)
    }
    
    let geoSearch = geoLocation.flatMap { (location) in
      return ApiController.shared.currentWeather(lat:
        location.coordinate.latitude, lon: location.coordinate.longitude)
        .debug("ApiController: location")
          .catchErrorJustReturn(ApiController.Weather.dummy)
    }
    .share(replay: 1, scope: .forever)
    
    style()
    
    let searchInput =
    searchCityName.rx.controlEvent(.editingDidEndOnExit).asObservable()
        .debug("searchInput")
      .map({ self.searchCityName.text })
      .filter({ ($0 ?? "").count > 0 })
    .share(replay: 1, scope: .forever)
    
    let textSearch = searchInput.flatMap { (text) in
      return ApiController.shared.currentWeather(city: text ?? "Error")
        .debug("ApiController: text")
        .catchErrorJustReturn(ApiController.Weather.dummy)
    }
    .share(replay: 1, scope: .forever)
    
    mapButton.rx.tap
      .subscribe(onNext: {
        self.mapView.isHidden = !self.mapView.isHidden
      })
      .disposed(by: bag)
    
    mapView.rx.setDelegate(self)
      .disposed(by: bag)
    
    let mapInput = mapView.rx.regionDidChangeAnimated
        .debug("regionDidChangeAnimated")
        .skip(1)//“skip(1) prevents the application from firing a search right after the mapView has initialized.”
        .map { (_) in
            self.mapView.centerCoordinate
    }
    .share(replay: 1, scope: .forever)
    
    let mapSearch = mapInput.flatMap { (coordinate) in
      return ApiController.shared.currentWeather(lat: coordinate.latitude, lon: coordinate.longitude)
        .debug("ApiController: coordinate")
        .catchErrorJustReturn(ApiController.Weather.dummy)
        .share(replay: 1, scope: .forever)
    }
    
//    let surroundingMapSearch = mapInput.flatMap { (coordinate) in
//      return ApiController.shared.currentWeatherAround(lat: coordinate.latitude, lon: coordinate.longitude)
//        .catchErrorJustReturn([ApiController.Weather.dummy])
//    }
//
    let search = Observable.from([geoSearch,
                                  textSearch,
                                  mapSearch])
                           .merge()
                           .asDriver(onErrorJustReturn: ApiController.Weather.dummy)
    
    search.map({ [$0.overlay()] })
      .drive(mapView.rx.overlays)//Tap -> subscribed
      .disposed(by: bag)
    
//    “The difference between Driver and Signal is a bit like between BehaviorSubject and PublishSubject. After you’ve written RxSwift code for a while, you usually figure out the nuances of when to use which.
//    To help you decide which to use, simply ask yourself: “Do I need a replay of the last event when I connect to the resource?"
//    If your answer is no, then Signal is a good option; otherwise, Driver is the solution.”
//    
//    Excerpt From: By Marin Todorov. “RxSwift - Reactive Programming with Swift.” Apple Books.
    
    let running = Observable.from([searchInput.map({ _ in true }),
                                   geoInput.map({ _ in true }),
                                   mapInput.map({ _ in true }),
                                   search.map({ _ in false }).asObservable()])
                            .merge()
                            .startWith(true)
                            .asDriver(onErrorJustReturn: false)
    
    running
      .skip(1)
      .drive(activityIndicator.rx.isAnimating) //Tap -> subscribed
      .disposed(by: bag)

    search.map { "\($0.temperature)° C" }
      .drive(tempLabel.rx.text)
      .disposed(by: bag)

    search.map { $0.icon }
      .drive(iconLabel.rx.text)
      .disposed(by: bag)

    search.map { "\($0.humidity)%" }
      .drive(humidityLabel.rx.text)
      .disposed(by: bag)

    search.map { $0.cityName }
      .drive(cityNameLabel.rx.text)
      .disposed(by: bag)
    
    // Challenge 1

    let geoAndTextSearch = Observable.from([geoSearch, textSearch])
      .merge()
      .asDriver(onErrorJustReturn: ApiController.Weather.dummy)


    geoAndTextSearch.map({ $0.coordinate })
      .drive(mapView.rx.givenLocation) //Tap -> subscribed
      .disposed(by: bag)

    // Challenge 2

    mapInput.flatMap { (location) in
      return ApiController.shared.currentWeatherAround(lat: location.latitude, lon: location.longitude)
        .debug("ApiController currentWeatherAround")
        .catchErrorJustReturn([])
        .share(replay: 1, scope: .forever)
      }
      .asDriver(onErrorJustReturn: [])
      .map({ $0.map({ $0.overlay() }) })
      .drive(mapView.rx.overlays)
      .disposed(by: bag)
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

extension ViewController: MKMapViewDelegate {
  
  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    if let overlay = overlay as? ApiController.Weather.Overlay {
      let overlayView = ApiController.Weather.OverlayView(overlay: overlay, overlayIcon: overlay.icon)
      return overlayView
    }
    return MKOverlayRenderer()
  }
  
}

