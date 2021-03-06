--------------------------------------------------------------------------------
-- This file is part of the 'Minimalistic SDHC Host Reader'
-- Copyright (C) 2016 Paulino Ruiz-de-Clavijo Vázquez <paulino@dte.us.es>
-- Licensed under the Apache License 2.0, you may obtain a copy of 
-- the License at https://www.apache.org/licenses/LICENSE-2.0
--
-- You can get more info at https://github.com/paulino/minsdhcspi-host
--------------------------------------------------------------------------------
-- Date:    28-07-2017
-- Version: 1.1
--*--------------------------------- End auto header, don't touch this line -*--


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.sdspihost_pk.ALL;

-- Some notes
-- When error is detected, err signal is asserted until the unit is reset
-- Abort read is not implemented with CMD12.


entity sdspihost is
   Port ( 
   clk        : in  std_logic;
   reset      : in  std_logic;
   busy       : out std_logic;
   err        : out std_logic;
   
   r_block    : in  std_logic;
   r_byte     : in  std_logic; -- each byte is gotten asserting nb and waiting to fall of busy signal
   block_addr : in  std_logic_vector(31 downto 0); -- 512 SD block address
   data_out   : out std_logic_vector(7  downto 0);
        
   miso       : in  std_logic;  -- SD Card pin
   mosi       : out std_logic;  -- SD Card pin
   sclk       : out std_logic;  -- SD Card pin
   ss         : out std_logic   -- SD Card pin
    );
end sdspihost;

architecture Behavioral of sdspihost is


  component sdcmd
   Port (       
    clk       : in  std_logic;
    reset     : in  std_logic;
    argument  : in  std_logic_vector (31 downto 0);
    data_in   : in  std_logic_vector (7 downto 0); 
    data_out  : out std_logic_vector (7 downto 0);
    w_cmd     : in  std_logic;
    w_byte    : in  std_logic;
    w_arg     : in  std_logic;
    busy      : out std_logic;
      
    miso      : in std_logic;   -- SD Card pin
    mosi      : out std_logic;  -- SD Card pin
    sclk      : out std_logic;  -- SD Card pin
    ss        : out std_logic   -- SD Card pin
    );
  end component;

signal sdcmd_reset,sdcmd_w_arg    : std_logic;
signal sdcmd_w_byte,sdcmd_w_cmd   : std_logic;
signal sdcmd_busy     : std_logic;
signal sdcmd_data_out : std_logic_vector (7 downto 0);
signal sdcmd_data_in  : std_logic_vector (7 downto 0); 

signal counter_reset,counter_up : std_logic;
signal counter_dout : std_logic_vector(15 downto 0);

--signal out_reg_w:std_logic;


type state_type is (
  ST_INIT_0,ST_INIT_1,
  ST_CMD0_A,ST_CMD0_B,ST_CMD0_C,
  ST_CMD8_A,ST_CMD8_B,ST_CMD8_C,
  ST_CMD55_A,ST_CMD55_B,ST_CMD55_C,
  ST_ACMD41_A,ST_ACMD41_B,ST_ACMD41_C,
  ST_READ_BLOCK,ST_WAIT_BLOCK,ST_WAIT_TOKEN_FE,ST_WAIT_RBYTE,ST_WAIT_BYTE,
  ST_ABORTREAD_0,
  ST_IDLE,ST_ERR
   );
  
signal current_st,next_st: state_type;


begin

  u_sdcmd: sdcmd port map(
    clk       => clk,
    reset     => sdcmd_reset,
    argument  => block_addr,
    data_in   => sdcmd_data_in,
    data_out  => sdcmd_data_out,
    w_cmd     => sdcmd_w_cmd,
    w_byte    => sdcmd_w_byte,
    w_arg     => sdcmd_w_arg,
    busy      => sdcmd_busy,
      
    miso      => miso,
    mosi      => mosi,
    sclk      => sclk,
    ss        => ss
  );
   
u_counter: generic_counter   -- 16 bits counter to use
generic map (width => 16) 
port map(
    clk    =>  clk,
    reset  =>  counter_reset,
    up     =>  counter_up,
    dout   =>  counter_dout
  );
   

-- Direct conections

data_out <= sdcmd_data_out;


-- State machine

process (clk, reset)
  begin
  if (rising_edge(clk)) then
   if (reset='1') then
      current_st <= ST_INIT_0;  --default state on reset.
   else
      current_st <= next_st;   --state change.
   end if;
  end if;
end process;

process (current_st,sdcmd_busy,sdcmd_data_out,counter_dout,r_block,r_byte)
begin
  --sdcmd_data_in <=  CMD0_ROMADDR;
  busy <= '0';
  err  <= '0';
  sdcmd_data_in <= X"FF"; -- default
  sdcmd_reset   <= '0';
  sdcmd_w_cmd   <= '0';
  sdcmd_w_byte  <= '0';
  sdcmd_w_arg   <= '0';
  sdcmd_reset   <= '0';
  counter_reset <= '0';
  counter_up    <= '0'; 

  --out_reg_w     <= '0';
  
  case current_st is
     when ST_INIT_0 =>     -- Reset SDCMD module
       busy <= '1';
       sdcmd_reset <= '1'; -- Keep stopped
       next_st <= ST_INIT_1;
     when ST_INIT_1 =>  -- Wait for reset
       busy <= '1';
       if sdcmd_busy='1' then
         next_st <= ST_INIT_1;
       else
         next_st <= ST_CMD0_A;
         counter_reset <= '1'; -- Try twice CMD0
       end if;
  
    -- Send CMD0  
     when ST_CMD0_A =>
       busy <= '1';
       sdcmd_data_in <=  CMD0_ROMADDR;
       sdcmd_w_cmd  <= '1';
       next_st      <= ST_CMD0_B;
     when ST_CMD0_B => -- Wait response
       busy <= '1';
       if sdcmd_busy = '1' then
         next_st <= ST_CMD0_B;
       else
         next_st <= ST_CMD0_C;
       end if;
     when ST_CMD0_C => 
       busy <='1';
       counter_up <= '1';
       if sdcmd_data_out = X"01" then -- Check response
         next_st <= ST_CMD8_A;
       else
         if counter_dout(1) = '1' then -- no more retries
           next_st <= ST_ERR;
         else
           next_st <= ST_CMD0_A; -- try again
         end if;
       end if;
     
     -- Send CMD8
     when ST_CMD8_A =>  
       busy <= '1';
       sdcmd_data_in <=  CMD8_ROMADDR;
       sdcmd_w_cmd  <= '1';
       next_st      <= ST_CMD8_B;
     when ST_CMD8_B => -- Wait response
       busy <= '1';
       if sdcmd_busy = '1' then
         next_st <= ST_CMD8_B;
       else
         next_st <= ST_CMD8_C;
       end if;
     when ST_CMD8_C => 
       busy <='1';
       if sdcmd_data_out = X"01" then --  Check response
         next_st <= ST_CMD55_A;
         counter_reset <= '1'; 
       else
         next_st <= ST_ERR;
       end if;

     -- Send CMD55 try it several times
     when ST_CMD55_A =>  
       busy <= '1';
       counter_up <= '1';
       sdcmd_data_in <=  CMD55_ROMADDR;
       sdcmd_w_cmd  <= '1';
       if counter_dout(7 downto 0) = X"FF" then 
         next_st <= ST_ERR;
       else
         next_st <= ST_CMD55_B;
       end if;  
     when ST_CMD55_B => -- Wait response
       busy <= '1';
       if sdcmd_busy = '1' then
         next_st <= ST_CMD55_B;
       else
         next_st <= ST_CMD55_C;
       end if;
       
     when ST_CMD55_C =>
       busy <= '1';
       if sdcmd_data_out = X"FF" then
         next_st <= ST_CMD55_A;
       elsif sdcmd_data_out = X"01" then
       next_st <= ST_ACMD41_A; -- try init card
       else
         next_st <= ST_ERR;
       end if;
         
     -- Send ACMD41, wait until response 0x00 (bit idle cleared)
     when ST_ACMD41_A =>  
       busy <= '1';
       sdcmd_data_in <=  ACMD41_ROMADDR;
       sdcmd_w_cmd  <= '1';
       next_st      <= ST_ACMD41_B;
     when ST_ACMD41_B => -- Wait response
       busy <= '1';
       if sdcmd_busy = '1' then
         next_st <= ST_ACMD41_B;
       else
         next_st <= ST_ACMD41_C;
       end if;
     when ST_ACMD41_C => 
       busy <='1';
       counter_reset <= '1';  --  if try CMD55 again need it
       if sdcmd_data_out = X"00" then -- Init ends
        next_st <= ST_IDLE;         
       elsif sdcmd_data_out = X"01" then -- Init not ends, card is idle
        next_st <= ST_CMD55_A; -- try again 
     else
         next_st <= ST_ERR;
       end if;
       
   when ST_IDLE => -- Wait for read block
        if r_block = '1' then
          next_st <= ST_READ_BLOCK;
        else
          next_st <= ST_IDLE;
        end if;
      
   when ST_READ_BLOCK =>
      busy <= '1';
      if sdcmd_busy = '1' then
        next_st <= ST_READ_BLOCK;
      else    
        counter_reset <= '1';
        sdcmd_data_in <=  X"51"; -- CMD17 with argument (read block)
        sdcmd_w_cmd   <= '1';    -- CMD
        sdcmd_w_arg   <= '1';    -- Send 6 bytes command: data_in&argument&0x00 
        next_st <= ST_WAIT_BLOCK;
      end if;
      
    when ST_WAIT_BLOCK => -- Wait response 00 sending FF while not timeout
      busy <= '1';
      sdcmd_w_cmd   <= '1';  -- CMD
      sdcmd_w_arg   <= '1';  -- Send 6 bytes command: data_in&argument&0x00 
      if sdcmd_busy = '1' then
        next_st <= ST_WAIT_BLOCK;
      else
         counter_up <='1';
         if sdcmd_data_out = X"00" then -- Command OK
           counter_reset <= '1';
           sdcmd_w_byte  <= '1'; -- Send FF to wait token FE
           next_st <= ST_WAIT_TOKEN_FE;
         elsif counter_dout(9 downto 0) = X"3FF" then -- Time out
           next_st <= ST_ERR; 
         else
           sdcmd_w_byte  <= '1'; -- Try again sending 00
           next_st <= ST_WAIT_BLOCK;
         end if;
      end if;
     
    when ST_WAIT_TOKEN_FE => -- Now wait start token FE sending 0x00, after it data can be retrieved
      busy <= '1';
      sdcmd_w_cmd   <= '1';   -- CMD keep asserted
      if sdcmd_busy = '1' then
        next_st <= ST_WAIT_TOKEN_FE;
      else 
        counter_up <='1';
        if sdcmd_data_out = X"FE" then -- data ready
          counter_reset <= '1';  -- used to count 512 bytes  
          sdcmd_w_byte  <= '1';  -- Get first byte
          next_st <= ST_WAIT_BYTE;
        elsif counter_dout(9 downto 0) = X"3FF" then -- Timeout
          next_st <= ST_ERR;
        else
          sdcmd_w_byte  <= '1'; -- Try again sending FF
          next_st <= ST_WAIT_TOKEN_FE;
        end if;
      end if;
      
    when ST_WAIT_BYTE =>
      busy <= '1';
      sdcmd_w_cmd   <= '1';  -- CMD keep asserted data_in <= 0xFF   
      if sdcmd_busy = '1' then
         next_st <= ST_WAIT_BYTE;
      else
         next_st <= ST_WAIT_RBYTE; -- Next byte
      end if;
      
    when ST_WAIT_RBYTE => -- Data ready, now read other byte when R_BYTE is asserted
      busy <= '0';
      sdcmd_w_cmd   <= '1';  -- CMD keep asserted
      if r_block = '0' then  -- Abort read block
         next_st <= ST_ABORTREAD_0;
      else
        if r_byte = '1' then -- Wait for byte request
          sdcmd_w_byte  <= '1'; -- Byte request
          counter_up  <= '1';   -- Next byte counter
          next_st     <= ST_WAIT_BYTE;
        else
          next_st <= ST_WAIT_RBYTE;
        end if;
      end if;      
      
    when ST_ABORTREAD_0 =>
      busy <= '1';
      sdcmd_w_cmd   <= '1';  -- CMD keep asserted      
      sdcmd_w_byte  <= '1';  -- Sending bytes when busy fall
      if sdcmd_busy = '1' then
        next_st <= ST_ABORTREAD_0;
      else
        if counter_dout = "1000000001" then -- wait 512 + 2 bytes
          next_st <= ST_IDLE;
          sdcmd_w_cmd   <= '0';
          sdcmd_w_byte  <= '0';
        else
          counter_up <='1';
          next_st <= ST_ABORTREAD_0;
        end if;
      end if;
      
             
    when ST_ERR =>
       err <= '1';
       next_st <= ST_ERR;
  end case;
end process;

end Behavioral;
