require 'thread'

# Variável compartilhada entre threads
counter = 0

# Cria múltiplas threads que incrementam o contador
threads = 10.times.map do
  Thread.new do
    1000.times do
      current_value = counter
      sleep(0.0001) # Simula IO
      counter = current_value + 1
    end
  end
end

# Esperar todas as threads terminarem
threads.each(&:join)

puts "Valor final do contador: #{counter}"
# => Valor final do contador: 1000
