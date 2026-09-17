import Foundation

/// What goes on the Study tab's horizontal shelves.
///
/// Pure, so the rules are unit tests rather than something to count by eye on
/// a device: the visible shelf is capped, favorites are filtered out *before*
/// the cap rather than after it, and the history itself is never truncated —
/// only what is put on screen.
enum StudyShelf {
    /// How many recently studied items the shelf shows. A shelf that runs
    /// past the edge of two swipes is a list, not a shelf.
    static let recentLimit = 6

    /// The recently studied items to draw, newest first.
    ///
    /// `history` is deliberately a wider window than `recentLimit`: filtering
    /// an already-capped list meant that favoriting the most recent elements
    /// emptied the shelf even with plenty of others studied today.
    static func recent(from history: [Int], isFavorite: (Int) -> Bool) -> [Int] {
        Array(history.filter { !isFavorite($0) }.prefix(recentLimit))
    }
}
