require 'forwardable'

# wrapper class for input stream so that HTTP doesn't blow up when using it 
# ie. calling size() and rewind()
class Morpheus::BodyIO
  extend Forwardable

  def initialize(io)
    @io = io
  end

  def size
    0
  end

  def rewind
    nil
  end

  def_delegators :@io, :read, :readpartial, :write
  
end