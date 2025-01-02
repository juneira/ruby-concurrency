fiber = Fiber.new do
  Fiber.yield 1
  2
end

puts fiber.resume
puts fiber.resume
puts fiber.resume
