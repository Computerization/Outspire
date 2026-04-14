import Foundation
import SwiftSoup

/// Timetable item shape (simple form)
struct V2TimetableItem: Codable {
    let day: String
    let period: Int
    let start: String?
    let end: String?
    let course: String?
    let room: String?
    let teacher: String?

    enum CodingKeys: String, CodingKey {
        case day = "Day"
        case period = "Period"
        case start = "Start"
        case end = "End"
        case course = "Course"
        case room = "Room"
        case teacher = "Teacher"
    }
}

/// Alternate timetable payload observed in HAR: Data contains WeekList and TimetableList
struct V2TimetableAltResponse: Codable {
    struct LessonSlot: Codable {
        /// Some pages provide LessonNumber as string; not strictly required for mapping
        let LessonNumber: String?
        /// TimetableList arrays may include null entries for days without classes
        let TimetableList: [LessonItem?]
    }

    struct LessonItem: Codable {
        let WeekNumber: Int
        let LessonNumber: Int
        let SubjectName: String?
        let ClassRoomNo: String?
        let TeacherName: String?
    }

    let TimetableList: [LessonSlot]
}

struct YearOption: Codable, Equatable { let id: String; let name: String }

/// Service facade for timetable on TSIMS (new). Includes an HTML scraper for year options.
final class TimetableServiceV2 {
    static let shared = TimetableServiceV2()
    private init() {}

    /// Scrape /Stu/Timetable/Index for <select id="YearId"> options
    func fetchYearOptions(completion: @escaping (Result<[YearOption], NetworkError>) -> Void) {
        let path = "/Stu/Timetable/Index"
        // Fetch as HTML using a simple GET
        var request = URLRequest(url: URL(string: Configuration.tsimsV2BaseURL + path)!)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Safari",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7", forHTTPHeaderField: "Accept-Language")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if Configuration.debugNetworkLogging, let http = response as? HTTPURLResponse {
                    print("[TimetableV2] GET /Stu/Timetable/Index status=\(http.statusCode)")
                }
                if let error { completion(.failure(.requestFailed(error))); return }
                guard let data, let html = String(data: data, encoding: .utf8) else {
                    completion(.failure(.noData)); return
                }
                // If got redirected to Login page, signal unauthorized
                if html.lowercased().contains("/home/login") || html.lowercased().contains("login") && !html
                    .lowercased().contains("#yearid")
                {
                    if Configuration
                        .debugNetworkLogging { print("[TimetableV2] Unauthorized when fetching year options") }
                    completion(.failure(.unauthorized))
                    return
                }
                do {
                    let doc = try SwiftSoup.parse(html)
                    var options: [YearOption] = []
                    let selects = try doc.select("#YearId, #ddlYear, select[id*=Year], select[name*=Year]")
                    if let select = selects.first() {
                        let elems = try select.select("option")
                        for opt in elems.array() {
                            let id = try opt.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = try opt.text().trimmingCharacters(in: .whitespacesAndNewlines)
                            if !id.isEmpty { options.append(YearOption(id: id, name: name)) }
                        }
                    }
                    if Configuration.debugNetworkLogging { print("[TimetableV2] Year options count=\(options.count)") }
                    completion(.success(options))
                } catch {
                    completion(.failure(.requestFailed(error)))
                }
            }
        }.resume()
    }

    /// Fetch timetable JSON and return raw items
    func fetchTimetable(
        yearId: String,
        studentId: String? = nil,
        completion: @escaping (Result<[V2TimetableItem], NetworkError>) -> Void
    ) {
        var form: [String: String] = ["yearId": yearId]
        if let sid = studentId, !sid.isEmpty { form["studentId"] = sid }
        TSIMSClientV2.shared.postFormRaw(path: "/Stu/Timetable/GetTimetableByStudent", form: form) { result in
            switch result {
            case let .failure(err): completion(.failure(err))
            case let .success(data):
                // Try simple array first
                if let env = try? JSONDecoder().decode(ApiResponse<[V2TimetableItem]>.self, from: data), env.isSuccess {
                    if Configuration
                        .debugNetworkLogging
                    {
                        print("[TimetableV2] Decoded simple items count=\(env.data?.count ?? 0)")
                    }
                    completion(.success(env.data ?? []))
                    return
                }
                // Try alternate shape
                if let env2 = try? JSONDecoder().decode(ApiResponse<V2TimetableAltResponse>.self, from: data),
                   env2.isSuccess, let alt = env2.data
                {
                    var items: [V2TimetableItem] = []
                    for slot in alt.TimetableList {
                        for itOpt in slot.TimetableList {
                            guard let it = itOpt else { continue }
                            let dayName: String = [
                                1: "Monday",
                                2: "Tuesday",
                                3: "Wednesday",
                                4: "Thursday",
                                5: "Friday"
                            ][it.WeekNumber] ?? String(it.WeekNumber)
                            items.append(V2TimetableItem(
                                day: dayName,
                                period: it.LessonNumber,
                                start: nil,
                                end: nil,
                                course: it.SubjectName,
                                room: it.ClassRoomNo,
                                teacher: it.TeacherName
                            ))
                        }
                    }
                    if Configuration
                        .debugNetworkLogging { print("[TimetableV2] Decoded alt items count=\(items.count)") }
                    completion(.success(items))
                    return
                }
                if Configuration.debugNetworkLogging, let preview = String(data: data, encoding: .utf8)?.prefix(200) {
                    print("[TimetableV2] Unexpected format preview=\(preview)")
                }
                completion(.failure(.decodingError(NSError(
                    domain: "Timetable",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected timetable format"]
                ))))
            }
        }
    }
}
