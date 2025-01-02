fiber = Fiber.new do |first|
  second = (Fiber.yield first + 2) + 5
  second
end

puts fiber.resume 10
puts fiber.resume 14
puts fiber.resume 232
