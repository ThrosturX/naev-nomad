local loaded, api = pcall(require, "crewmates.api")

return {
   api = loaded and api or nil,
}
