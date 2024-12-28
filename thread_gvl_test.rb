def test_gvl
  arr = []

  threads = 10.times.map do
    Thread.new do
      100.times do
        arr << 1 # Inserir elementos no array não é uma operação atomica!
      end
    end
  end

  threads.each(&:join)

  if arr.count != 1000
    # 10 Threads inserindo 100 elementos no array = 1000 elementos
    puts "Era esperado 1000 elementos, mas existem %d elementos" % arr.count

    return true
  end

  false
end

# É necessário rodar o teste mais de uma vez
10.times do
  break if test_gvl
end

puts "Fim do teste"
