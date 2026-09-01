// Opens the app in a full tab rather than a cramped popup. The page itself does
// all the work; this exists only to give the toolbar button somewhere to go.
chrome.action.onClicked.addListener(function () {
  chrome.tabs.create({ url: chrome.runtime.getURL('index.html') });
});
