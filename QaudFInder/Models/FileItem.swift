//
//  FileItem.swift
//  QuadFinder — 파일 한 개의 정보와 보기·정렬 방식
//

import Foundation

// MARK: - 보기 방식

enum ViewMode: String {
    case list
    case icon
}

// MARK: - 정렬 기준 (리스트 보기의 열 제목을 누르면 바뀜)

enum SortKey: String {
    case name       // 이름
    case modified   // 수정일
    case size       // 크기
    case kind       // 종류
}

// MARK: - 파일/폴더 한 개의 정보

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool   // 들어갈 수 있는 폴더인지 (.app 같은 패키지는 파일로 취급)
    let size: Int64?        // 폴더는 nil
    let modified: Date?
    let kind: String        // "폴더", "PDF 문서" 같은 종류 설명
    let isHidden: Bool      // 숨김 파일 (흐리게 표시)
    var id: URL { url }
}
