local bint = require('.bint')(256)
local ao = require('ao')
--[[
  This module implements the ao Standard Token Specification.

  Terms:
    Sender: the wallet or Process that sent the Message

  It will first initialize the internal state, and then attach handlers,
    according to the ao Standard Token Spec API:

    - Info(): return the token parameters, like Name, Ticker, Logo, and Denomination

    - Balance(Target?: string): return the token balance of the Target. If Target is not provided, the Sender
        is assumed to be the Target

    - Balances(): return the token balance of all participants

    - Transfer(Target: string, Quantity: number): if the Sender has a sufficient balance, send the specified Quantity
        to the Target. It will also issue a Credit-Notice to the Target and a Debit-Notice to the Sender

    - Mint(Quantity: number): if the Sender matches the Process Owner, then mint the desired Quantity of tokens, adding
        them the Processes' balance
]]
--
local json = require('json')

--[[
     Initialize State

     ao.id is equal to the Process.Id
   ]]
--
if not Balances then Balances = { [ao.id] = tostring(bint(10000 * 1e12)) } end

if not BurnReqs then BurnReqs = {} end

if not MemIds then MemIds = {} end

if Name ~= 'MEM Wrapped USDT' then Name = 'MEM Wrapped USDT' end

if Ticker ~= 'mwUSDT' then Ticker = 'mwUSDT' end

if Denomination ~= 18 then Denomination = 18 end

if not Logo then Logo = 'zxSMuOKdCXL2LV2mYO0RJ1Cw_uP15lFDRb1UMoxHxXA' end

--[[
     Add handlers for each incoming Action defined by the ao Standard Token Specification
   ]]
--

--[[
     Info
   ]]
--
Handlers.add('info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
  ao.send({
    Target = msg.From,
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination)
  })
end)

--[[
     Balance
   ]]
--
Handlers.add('balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
  local bal = '0'

  -- If not Recipient is provided, then return the Senders balance
  if (msg.Tags.Recipient and Balances[msg.Tags.Recipient]) then
    bal = Balances[msg.Tags.Recipient]
  elseif Balances[msg.From] then
    bal = Balances[msg.From]
  end

  ao.send({
    Target = msg.From,
    Balance = bal,
    Ticker = Ticker,
    Account = msg.Tags.Recipient or msg.From,
    Data = bal
  })
end)

--[[
     Balances
   ]]
--
Handlers.add('balances', Handlers.utils.hasMatchingTag('Action', 'Balances'),
  function(msg) ao.send({ Target = msg.From, Data = json.encode(Balances) }) end)

--[[
     Transfer
   ]]
--
Handlers.add('transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
  assert(type(msg.Recipient) == 'string', 'Recipient is required!')
  assert(type(msg.Quantity) == 'string', 'Quantity is required!')
  assert(bint.__lt(0, bint(msg.Quantity)), 'Quantity must be greater than 0')

  if not Balances[msg.From] then Balances[msg.From] = "0" end
  if not Balances[msg.Recipient] then Balances[msg.Recipient] = "0" end

  local qty = bint(msg.Quantity)
  local balance = bint(Balances[msg.From])
  if bint.__le(qty, balance) then
    Balances[msg.From] = tostring(bint.__sub(balance, qty))
    Balances[msg.Recipient] = tostring(bint.__add(Balances[msg.Recipient], qty))

    --[[
         Only send the notifications to the Sender and Recipient
         if the Cast tag is not set on the Transfer message
       ]]
    --
    if not msg.Cast then
      -- Send Debit-Notice to the Sender
      ao.send({
        Target = msg.From,
        Action = 'Debit-Notice',
        Recipient = msg.Recipient,
        Quantity = tostring(qty),
        Data = Colors.gray ..
            "You transferred " ..
            Colors.blue .. msg.Quantity .. Colors.gray .. " to " .. Colors.green .. msg.Recipient .. Colors.reset
      })
      -- Send Credit-Notice to the Recipient
      ao.send({
        Target = msg.Recipient,
        Action = 'Credit-Notice',
        Sender = msg.From,
        Quantity = tostring(qty),
        Data = Colors.gray ..
            "You received " ..
            Colors.blue .. msg.Quantity .. Colors.gray .. " from " .. Colors.green .. msg.Recipient .. Colors.reset
      })
    end
  else
    ao.send({
      Target = msg.From,
      Action = 'Transfer-Error',
      ['Message-Id'] = msg.Id,
      Error = 'Insufficient Balance!'
    })
  end
end)

--[[
    Mint
   ]]
--
Handlers.add('mint', Handlers.utils.hasMatchingTag('Action', 'Mint'), function(msg)
  assert(type(msg.Quantity) == 'string', 'Quantity is required!')
  assert(type(msg.Address) == 'string', 'Address required!')
  assert(type(msg.MemId) == 'string', 'MemId is Required!')
  assert(MemIds[msg.MemId] == nil, 'MemId already exists!')
  assert(bint.__lt(0, msg.Quantity), 'Quantity must be greater than zero!')

  local address = msg.Address
  if not Balances[address] then Balances[address] = "0" end

  if msg.From == "vZY2XY1RD9HIfWi8ift-1_DnHLDadZMWrufSh-_rKF0" then
    -- Add tokens to the token pool, according to Quantity
    Balances[address] = tostring(bint.__add(Balances[address], msg.Quantity))
    MemIds[msg.MemId] = true
    
      ao.send({
      Target = address,
      Data = Colors.gray .. "Successfully minted " .. Colors.blue .. msg.Quantity .. Colors.reset
    })
  else
    ao.send({
      Target = address,
      Action = 'Mint-Error',
      ['Message-Id'] = msg.Id,
      Error = 'Only the Process Id can mint new ' .. Ticker .. ' tokens!'
    })
  end
end)

--[[
     Burn
   ]]
--
Handlers.add('burn', Handlers.utils.hasMatchingTag('Action', 'Burn'), function(msg)
  assert(type(msg.Quantity) == 'string', 'Quantity is required!')
  assert(bint.__lt(0, bint(msg.Quantity)), 'Quantity must be greater than 0')

  -- if not Balances[msg.From] then Balances[msg.From] = "0" end
  -- if not Balances[msg.Recipient] then Balances[msg.Recipient] = "0" end

  local qty = bint(msg.Quantity)
  local balance = bint(Balances[msg.From])
  if bint.__le(qty, balance) then
    Balances[msg.From] = tostring(bint.__sub(balance, qty))
      
    BurnReqs[msg.Id] = {
        qty = tostring(qty),
        caller = msg.From,
    }

    --[[
         Only send the notifications to the Sender and Recipient
         if the Cast tag is not set on the Transfer message
       ]]
    --
    if not msg.Cast then
      -- Send Debit-Notice to the Sender
      ao.send({
        Target = msg.From,
        Action = 'Debit-Notice',
        Quantity = tostring(qty),
        Data = Colors.gray ..
            "You Burned " ..
            Colors.blue .. msg.Quantity 
      })
      -- Send Credit-Notice to the Recipient
    end
  else
    ao.send({
      Target = msg.From,
      Action = 'Transfer-Error',
      ['Message-Id'] = msg.Id,
      Error = 'Insufficient Balance!'
    })
  end
end)


