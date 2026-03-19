module Streamable
  extend ActiveSupport::Concern

  private

  def set_streaming_headers(filename, content_type: "text/event-stream;charset='utf-8';header=present")
    response.headers.delete('Content-Length')
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, private'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    response.headers['Content-Type'] = content_type
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['ETag'] = '0'
    response.headers['Last-Modified'] = '0'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}"
  end
end
