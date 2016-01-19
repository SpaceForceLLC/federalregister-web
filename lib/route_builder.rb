module RouteBuilder
  include RouteBuilder::Documents
  include RouteBuilder::PublicInspectionDocuments
  include RouteBuilder::Citations
  include RouteBuilder::ExternalUrls
  include RouteBuilder::Fr2ApiUrls
  include RouteBuilder::Fr2Urls
  include RouteBuilder::BlogUrls
end
