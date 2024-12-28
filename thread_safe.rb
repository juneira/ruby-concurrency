require 'thread'

# Variável compartilhada entre threads
counter = 0

# Cria uma intância compartilhada do mutex
mutex = Mutex.new

# Cria múltiplas threads que incrementam o contador
threads = 10.times.map do
  Thread.new do
    1000.times do
      mutex.synchronize do
        current_value = counter
        sleep(0.0001) # Simula IO
        counter = current_value + 1
      end
    end
  end
end

# Espera todas as threads terminarem
threads.each(&:join)

puts "Valor final do contador: #{counter}"
# => Valor final do contador: 10000
