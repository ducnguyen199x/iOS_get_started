//
//  SearchViewController.swift
//  HalfTunes
//
//  Created by Ken Toh on 13/7/15.
//  Copyright (c) 2015 Ken Toh. All rights reserved.
//

import UIKit
import MediaPlayer

class SearchViewController: UIViewController {

  let defaultSession = URLSession(configuration: .default)
  var dataTask: URLSessionDataTask?
  var activeDownloads = [String: Download]()
  
  @IBOutlet weak var tableView: UITableView!
  @IBOutlet weak var searchBar: UISearchBar!

  var searchResults = [Track]()
  
  lazy var tapRecognizer: UITapGestureRecognizer = {
    var recognizer = UITapGestureRecognizer(target:self, action: #selector(SearchViewController.dismissKeyboard))
    return recognizer
  }()
  
  // MARK: View controller methods
  lazy var downloadsSession: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: "bgSessionConfiguration")
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    return session
  }()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    _ = self.downloadsSession
    tableView.tableFooterView = UIView()
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  // MARK: Handling Search Results
  
  // This helper method helps parse response JSON NSData into an array of Track objects.
  func updateSearchResults(_ data: Data?) {
    searchResults.removeAll()
    do {
      if let data = data, let response = try JSONSerialization.jsonObject(with: data, options:JSONSerialization.ReadingOptions(rawValue:0)) as? [String: AnyObject] {
        print(response)
        // Get the results array
        if let array: AnyObject = response["results"] {
          for trackDictonary in array as! [AnyObject] {
            if let trackDictonary = trackDictonary as? [String: AnyObject], let previewUrl = trackDictonary["previewUrl"] as? String {
              // Parse the search result
              let name = trackDictonary["trackName"] as? String
              let artist = trackDictonary["artistName"] as? String
              searchResults.append(Track(name: name, artist: artist, previewUrl: previewUrl))
            } else {
              print("Not a dictionary")
            }
          }
        } else {
          print("Results key not found in dictionary")
        }
      } else {
        print("JSON Error")
      }
    } catch let error as NSError {
      print("Error parsing results: \(error.localizedDescription)")
    }
    
    DispatchQueue.main.async {
      self.tableView.reloadData()
      self.tableView.setContentOffset(CGPoint.zero, animated: false)
    }
  }
  
  // MARK: Keyboard dismissal
  
  func dismissKeyboard() {
    searchBar.resignFirstResponder()
  }
  
  // MARK: Download methods
  
  // Called when the Download button for a track is tapped
  func startDownload(_ track: Track) {
    if let urlString = track.previewUrl, let url = URL(string: urlString) {
      // 1
      let download = Download(url: urlString)
      // 2
      download.downloadTask = downloadsSession.downloadTask(with: url)
      // 3
      download.downloadTask!.resume()
      // 4
      download.isDownloading = true
      // 5
      activeDownloads[download.url] = download
    }
  }
  
  // Called when the Pause button for a track is tapped
  func pauseDownload(_ track: Track) {
    if let urlString = track.previewUrl,
      let download = activeDownloads[urlString] {
      if(download.isDownloading) {
        download.downloadTask?.cancel { data in
          if data != nil {
            download.resumeData = data
          }
        }
        download.isDownloading = false
      }
    }
  }
  
  // Called when the Cancel button for a track is tapped
  func cancelDownload(_ track: Track) {
    if let urlString = track.previewUrl,
      let download = activeDownloads[urlString] {
      download.downloadTask?.cancel()
      activeDownloads[urlString] = nil
    }
  }
  
  // Called when the Resume button for a track is tapped
  func resumeDownload(_ track: Track) {
    if let urlString = track.previewUrl,
      let download = activeDownloads[urlString] {
      if let resumeData = download.resumeData {
        download.downloadTask = downloadsSession.downloadTask(withResumeData: resumeData)
        download.downloadTask!.resume()
        download.isDownloading = true
      } else if let url = URL(string: download.url) {
        download.downloadTask = downloadsSession.downloadTask(with: url)
        download.downloadTask!.resume()
        download.isDownloading = true
      }
    }
  }
  
   // This method attempts to play the local file (if it exists) when the cell is tapped
  func playDownload(_ track: Track) {
    if let urlString = track.previewUrl, let url = localFilePathForUrl(urlString) {
      let moviePlayer:MPMoviePlayerViewController! = MPMoviePlayerViewController(contentURL: url)
      presentMoviePlayerViewControllerAnimated(moviePlayer)
    }
  }
  
  // MARK: Download helper methods
  
  // This method generates a permanent local file path to save a track to by appending
  // the lastPathComponent of the URL (i.e. the file name and extension of the file)
  // to the path of the app’s Documents directory.
  func localFilePathForUrl(_ previewUrl: String) -> URL? {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
    if let url = URL(string: previewUrl) {
        let fullPath = documentsPath.appendingPathComponent(url.lastPathComponent)
        return URL(fileURLWithPath:fullPath)
    }
    return nil
  }
  
  // This method checks if the local file exists at the path generated by localFilePathForUrl(_:)
  func localFileExistsForTrack(_ track: Track) -> Bool {
    if let urlString = track.previewUrl, let localUrl = localFilePathForUrl(urlString) {
      var isDir : ObjCBool = false
      return FileManager.default.fileExists(atPath: localUrl.path, isDirectory: &isDir)
    }
    return false
  }
  
  func trackIndexForDownloadTask(downloadTask: URLSessionDownloadTask) -> Int? {
    if let url = downloadTask.originalRequest?.url?.absoluteString {
      for (index, track) in searchResults.enumerated() {
        if url == track.previewUrl! {
          return index
        }
      }
    }
    return nil
  }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    // Dimiss the keyboard
    dismissKeyboard()
    
    if !searchBar.text!.isEmpty {
      // 1
      if dataTask != nil {
        dataTask?.cancel()
      }
      // 2
      UIApplication.shared.isNetworkActivityIndicatorVisible = true
      // 3
      let expectedCharSet = NSCharacterSet.urlQueryAllowed
      guard let searchTerm = searchBar.text!.addingPercentEncoding(withAllowedCharacters: expectedCharSet) else { return }
      // 4
      let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&term=\(searchTerm)")
      
      // 5
      dataTask = defaultSession.dataTask(with: url!) {
        data, response, error in
        // 6
        DispatchQueue.main.async {
          UIApplication.shared.isNetworkActivityIndicatorVisible = false
        }
        // 7
        if let error = error {
          print(error.localizedDescription)
        } else if let httpResponse = response as? HTTPURLResponse {
          if httpResponse.statusCode == 200 {
            self.updateSearchResults(data)
          }
        }
      }
      // 8
      dataTask?.resume()
    }
  }
    
  func position(for bar: UIBarPositioning) -> UIBarPosition {
    return .topAttached
  }
    
  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    view.addGestureRecognizer(tapRecognizer)
  }
    
  func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
    view.removeGestureRecognizer(tapRecognizer)
  }
}

// MARK: TrackCellDelegate

extension SearchViewController: TrackCellDelegate {
  func pauseTapped(_ cell: TrackCell) {
    if let indexPath = tableView.indexPath(for: cell) {
      let track = searchResults[(indexPath as NSIndexPath).row]
      pauseDownload(track)
      tableView.reloadRows(at: [IndexPath(row: (indexPath as NSIndexPath).row, section: 0)], with: .none)
    }
  }
  
  func resumeTapped(_ cell: TrackCell) {
    if let indexPath = tableView.indexPath(for: cell) {
      let track = searchResults[(indexPath as NSIndexPath).row]
      resumeDownload(track)
      tableView.reloadRows(at: [IndexPath(row: (indexPath as NSIndexPath).row, section: 0)], with: .none)
    }
  }
  
  func cancelTapped(_ cell: TrackCell) {
    if let indexPath = tableView.indexPath(for: cell) {
      let track = searchResults[(indexPath as NSIndexPath).row]
      cancelDownload(track)
      tableView.reloadRows(at: [IndexPath(row: (indexPath as NSIndexPath).row, section: 0)], with: .none)
    }
  }
  
  func downloadTapped(_ cell: TrackCell) {
    if let indexPath = tableView.indexPath(for: cell) {
      let track = searchResults[(indexPath as NSIndexPath).row]
      startDownload(track)
      tableView.reloadRows(at: [IndexPath(row: (indexPath as NSIndexPath).row, section: 0)], with: .none)
    }
  }
}

// MARK: UITableViewDataSource

extension SearchViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return searchResults.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "TrackCell", for: indexPath) as!TrackCell
    
    // Delegate cell button tap events to this view controller
    cell.delegate = self
    
    let track = searchResults[(indexPath as NSIndexPath).row]
    
    // Configure title and artist labels
    cell.titleLabel.text = track.name
    cell.artistLabel.text = track.artist

    // If the track is already downloaded, enable cell selection and hide the Download button
    var showDownloadControls = false
    if let download = activeDownloads[track.previewUrl!] {
      showDownloadControls = true
      
      cell.progressView.progress = download.progress
      cell.progressLabel.text = (download.isDownloading) ? "Downloading..." : "Paused"
      
      let title = (download.isDownloading) ? "Pause" : "Resume"
      cell.pauseButton.setTitle(title, for: UIControlState.normal)
    }
    cell.progressView.isHidden = !showDownloadControls
    cell.progressLabel.isHidden = !showDownloadControls
    
    let downloaded = localFileExistsForTrack(track)
    cell.selectionStyle = downloaded ? UITableViewCellSelectionStyle.gray : UITableViewCellSelectionStyle.none
    cell.downloadButton.isHidden = downloaded || showDownloadControls
    
    cell.pauseButton.isHidden = !showDownloadControls
    cell.cancelButton.isHidden = !showDownloadControls
    
    return cell
  }
}

// MARK: UITableViewDelegate

extension SearchViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return 62.0
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let track = searchResults[(indexPath as NSIndexPath).row]
    if localFileExistsForTrack(track) {
      playDownload(track)
    }
    tableView.deselectRow(at: indexPath, animated: true)
  }
}

// MARK: URLSessionDownloadDelegate
extension SearchViewController: URLSessionDownloadDelegate {
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // 1
    if let originalURL = downloadTask.originalRequest?.url?.absoluteString,
      let destinationURL = localFilePathForUrl(originalURL) {
      
      print(destinationURL)
      
      // 2
      let fileManager = FileManager.default
      do {
        try fileManager.removeItem(at: destinationURL)
      } catch {
        // Non-fatal: file probably doesn't exist
      }
      do {
        try fileManager.copyItem(at: location, to: destinationURL)
      } catch let error as NSError {
        print("Could not copy file to disk: \(error.localizedDescription)")
      }
    }
    
    // 3
    if let url = downloadTask.originalRequest?.url?.absoluteString {
      activeDownloads[url] = nil
      // 4
      if let trackIndex = trackIndexForDownloadTask(downloadTask: downloadTask) {
        DispatchQueue.main.async {
          self.tableView.reloadRows(at: [IndexPath(row: trackIndex, section: 0)], with: .none)
        }
      }
    }
  }
  
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    // 1
    if let downloadUrl = downloadTask.originalRequest?.url?.absoluteString,
      let download = activeDownloads[downloadUrl] {
      // 2
      download.progress = Float(totalBytesWritten)/Float(totalBytesExpectedToWrite)
      // 3
      let totalSize = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: ByteCountFormatter.CountStyle.binary)
      // 4
      if let trackIndex = trackIndexForDownloadTask(downloadTask: downloadTask), let trackCell = tableView.cellForRow(at: IndexPath(row: trackIndex, section: 0)) as? TrackCell {
        DispatchQueue.main.async {
          trackCell.progressView.progress = download.progress
          trackCell.progressLabel.text =  String(format: "%.1f%% of %@",  download.progress * 100, totalSize)
        }
      }
    }
  }
  
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      if let completionHandler = appDelegate.backgroundSessionCompletionHandler {
        appDelegate.backgroundSessionCompletionHandler = nil
        DispatchQueue.main.async {
          completionHandler()
        }
      }
    }
  }
}

