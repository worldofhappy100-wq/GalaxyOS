-- SHA-256 (FIPS 180-4). All sums are reduced modulo 2^32.
local bits = bit32
local xor, and_, not_ = bits.bxor, bits.band, bits.bnot
local rr, sr = bits.rrotate, bits.rshift
local m = 4294967296
local primes = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function bytes(number)
    return string.char(sr(number, 24), and_(sr(number, 16), 255), and_(sr(number, 8), 255), and_(number, 255))
end

return function(data)
    local length = #data * 8
    data = data .. "\128" .. ("\0"):rep((55 - #data) % 64) .. bytes(math.floor(length / m)) .. bytes(length % m)
    local hash = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 }
    local w = {}
    for start = 1, #data, 64 do
        for j = 1, 16 do
            local p = start + (j - 1) * 4
            local a,b,c,d = data:byte(p, p + 3)
            w[j] = ((a * 256 + b) * 256 + c) * 256 + d
        end
        for j = 17, 64 do
            local a,b = w[j-15],w[j-2]
            w[j] = (w[j-16] + xor(rr(a, 7), rr(a, 18), sr(a, 3)) + w[j-7]
                + xor(rr(b, 17), rr(b, 19), sr(b, 10))) % m
        end
        local a,b,c,d,e,f,g,h = (table.unpack or unpack)(hash)
        for j = 1, 64 do
            local t1 = (h + xor(rr(e, 6), rr(e, 11), rr(e, 25))
                + xor(and_(e, f), and_(not_(e), g)) + primes[j] + w[j]) % m
            local t2 = (xor(rr(a, 2), rr(a, 13), rr(a, 22)) + xor(and_(a, b), and_(a, c), and_(b, c))) % m
            a,b,c,d,e,f,g,h = (t1+t2)%m,a,b,c,(d+t1)%m,e,f,g
        end
        local state = {a,b,c,d,e,f,g,h}
        for j = 1, 8 do hash[j] = (hash[j] + state[j]) % m end
    end
    return ("%08x%08x%08x%08x%08x%08x%08x%08x"):format((table.unpack or unpack)(hash))
end
