/*
 * Copyright (c) 2016 Razeware LLC
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


import Foundation
import RxSwift
import RxCocoa

class EONET {
    static let API = "https://eonet.sci.gsfc.nasa.gov/api/v2.1"
    static let categoriesEndpoint = "/categories"
    static let eventsEndpoint = "/events"

    static var ISODateReader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZ"
        return formatter
    }()
    
    static func request(endpoint: String, query:[String: Any] = [:]) -> Observable<[String: Any]> {
        do {
            guard let url = URL(string: API)?.appendingPathComponent(endpoint),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                    throw EOError.invalidURL(endpoint)
            }
            components.queryItems = try query.compactMap{ (key, value) -> URLQueryItem? in
                guard let v = value as? CustomStringConvertible else {
                    throw EOError.invalidParameter(key, value)
                }
                return URLQueryItem(name: key, value: v.description)
            }
            
            guard let finalURL = components.url else {
                throw EOError.invalidURL(endpoint)
            }
            let request = URLRequest(url: finalURL)
            
            let response = URLSession.shared.rx.response(request: request)
                .map { _, data -> [String: Any] in
                    guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                        let result = jsonObject as? [String: Any] else {
                            throw EOError.invalidJSON(finalURL.absoluteString)
                    }
                    return result
            }
            
            return response
            
        } catch{
            return Observable.empty()
        }
    }
    
    static var categories: Observable<[EOCategory]> = {
        let response: Observable<[String: Any]> = EONET.request(endpoint: categoriesEndpoint)
        let categoriesObservable: Observable<[EOCategory]> = response.map({ data -> [EOCategory] in
            let categories: [[String: Any]] = data["categories"] as? [[String: Any]] ?? []
            let categoriesToReturn: [EOCategory] = categories
                .compactMap(EOCategory.init)
                .sorted{ $0.name < $1.name }
            
            return categoriesToReturn
        })
        
        return categoriesObservable.share(replay: 1, scope: .forever)
    }()
    
    fileprivate static func events(forLast days: Int, closed: Bool, endpoint: String) -> Observable<[EOEvent]> {
        return request(endpoint: endpoint, query: [
            "days": NSNumber(value: days),
            "status": (closed ? "closed" : "open")
            ])
            .map{ (dic) -> [EOEvent] in
                guard let raw = dic["events"] as? [[String: Any]] else {
                    throw EOError.invalidJSON(endpoint)
                }
                return raw.compactMap(EOEvent.init)
            }
    }
    
    static func events(forLast days: Int = 360, category: EOCategory) -> Observable<[EOEvent]> {
        let openEvents = events(forLast: days, closed: false, endpoint: category.endpoint)
        let closedEvents = events(forLast: days, closed: true, endpoint: category.endpoint)
        
        return Observable.of(openEvents, closedEvents)
            .merge()
            .reduce([], accumulator: { (running, new) -> [EOEvent] in
                running + new
            })
    }
  
    static func filteredEvents(events: [EOEvent], forCategory category: EOCategory) -> [EOEvent] {
        return events.filter { event in
            return event.categories.contains(category.id) &&
                !category.events.contains {
                    $0.id == event.id
                }
            }
            .sorted(by: EOEvent.compareDates)
    }

}
