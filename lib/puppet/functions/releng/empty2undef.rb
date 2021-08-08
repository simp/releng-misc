# @summary Return `undef` when `obj.empty`, otherwise returns `obj`
#
# Returns the object if it's not empty (or doesn't respond to `.empty`), and
# `Undef` if it is empty.
#
# This is useful to ensure default data structures in `.then`/`.lest` chains.
Puppet::Functions.create_function(:'releng::empty2undef') do
  # @param obj The object to test
  # @return [Undef] If `obj` is empty
  # @return [Any] `obj`, if `obj` is not empty (or doesn't respond to `.empty`)
  dispatch :empty2undef do
    param 'Any', :obj
    return_type 'Any'
  end

  # @api private
  def empty2undef(obj)
    if obj.respond_to? :empty?
      return(nil) if obj.empty?
    end
    return obj
  end
end
