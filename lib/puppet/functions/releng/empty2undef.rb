# Return undef when obj.empty == true, otherwise returns obj
Puppet::Functions.create_function(:'releng::empty2undef') do
  dispatch :empty2undef do
    param 'Any', :obj
    return_type 'Any'
  end

  def empty2undef(obj)
    if obj.respond_to? :empty?
      return(nil) if obj.empty?
    end
    return obj
  end
end



