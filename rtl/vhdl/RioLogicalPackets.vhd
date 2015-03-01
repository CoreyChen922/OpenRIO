-------------------------------------------------------------------------------
-- 
-- RapidIO IP Library Core
-- 
-- This file is part of the RapidIO IP library project
-- http://www.opencores.org/cores/rio/
-- 
-- Description
-- Containing RapidIO packet parsers and generators.
-- 
-- To Do:
-- - Add support for maint-request and response in both directions.
-- - Add support for portWrite in both directions.
-- - Add generic to disable support for specified packets.
-- - Dont set complete before the packet is ready in inbound packet
--   handler.
-- - Add error indication if erronous sizes are received.
-- 
-- Author(s): 
-- - Magnus Rosenius, magro732@opencores.org 
-- 
-------------------------------------------------------------------------------
-- 
-- Copyright (C) 2014 Authors and OPENCORES.ORG 
-- 
-- This source file may be used and distributed without 
-- restriction provided that this copyright statement is not 
-- removed from the file and that any derivative work contains 
-- the original copyright notice and the associated disclaimer. 
-- 
-- This source file is free software; you can redistribute it 
-- and/or modify it under the terms of the GNU Lesser General 
-- Public License as published by the Free Software Foundation; 
-- either version 2.1 of the License, or (at your option) any 
-- later version. 
-- 
-- This source is distributed in the hope that it will be 
-- useful, but WITHOUT ANY WARRANTY; without even the implied 
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
-- PURPOSE. See the GNU Lesser General Public License for more 
-- details. 
-- 
-- You should have received a copy of the GNU Lesser General 
-- Public License along with this source; if not, download it 
-- from http://www.opencores.org/lgpl.shtml 
-- 
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- MaintenanceInbound
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rio_common.all;


-------------------------------------------------------------------------------
-- Entity for MaintenanceInbound.
-------------------------------------------------------------------------------
entity MaintenanceInbound is
  port(
    clk : in std_logic;
    areset_n : in std_logic;
    enable : in std_logic;

    readRequestReady_o : out std_logic;
    writeRequestReady_o : out std_logic;
    readResponseReady_o : out std_logic;
    writeResponseReady_o : out std_logic;
    portWriteReady_o : out std_logic;
    vc_o : out std_logic;
    crf_o : out std_logic;
    prio_o : out std_logic_vector(1 downto 0);
    tt_o : out std_logic_vector(1 downto 0);
    dstid_o : out std_logic_vector(31 downto 0);
    srcid_o : out std_logic_vector(31 downto 0);
    size_o : out std_logic_vector(3 downto 0);
    status_o : out std_logic_vector(3 downto 0);
    tid_o : out std_logic_vector(7 downto 0);
    hop_o : out std_logic_vector(7 downto 0);
    offset_o : out std_logic_vector(20 downto 0);
    wdptr_o : out std_logic;
    payloadLength_o : out std_logic_vector(2 downto 0);
    payloadIndex_i : in std_logic_vector(2 downto 0);
    payload_o : out std_logic_vector(63 downto 0);
    done_i : in std_logic;
    
    inboundCyc_i : in std_logic;
    inboundStb_i : in std_logic;
    inboundAdr_i : in std_logic_vector(7 downto 0);
    inboundDat_i : in std_logic_vector(31 downto 0);
    inboundAck_o : out std_logic);
end entity;


-------------------------------------------------------------------------------
-- Architecture for MaintenanceInbound.
-------------------------------------------------------------------------------
architecture MaintenanceInbound of MaintenanceInbound is

  type StateType is (RECEIVE_PACKET, READY);
  signal state : StateType;

  signal wdptr : std_logic;
  signal size : std_logic_vector(3 downto 0);

  signal inboundAck : std_logic;
  signal readRequestComplete : std_logic;
  signal writeRequestComplete : std_logic;
  signal readResponseComplete : std_logic;
  signal writeResponseComplete : std_logic;

  signal packetIndex : natural range 0 to 21;
  signal packetData : std_logic_vector(47 downto 0);

  signal memoryWrite : std_logic;
  signal memoryAddress : std_logic_vector(2 downto 0);
  signal memoryDataIn : std_logic_vector(63 downto 0);

begin

  readRequestReady_o <= readRequestComplete when (state = READY) else '0';
  writeRequestReady_o <= writeRequestComplete when (state = READY) else '0';
  readResponseReady_o <= readResponseComplete when (state = READY) else '0';
  writeResponseReady_o <= writeResponseComplete when (state = READY) else '0';
  portWriteReady_o <= '0';

  inboundAck_o <= inboundAck;
  MaintenanceRequest: process(clk, areset_n)
  begin
    if (areset_n = '0') then
      inboundAck <= '0';

      readRequestComplete <= '0';
      writeRequestComplete <= '0';
      readResponseComplete <= '0';
      writeResponseComplete <= '0';
      
      vc_o <= '0';
      crf_o <= '0';
      prio_o <= "00";
      tt_o <= "00";
      dstid_o <= (others=>'0');
      srcid_o <= (others=>'0');
      status_o <= (others=>'0');
      tid_o <= (others=>'0');
      hop_o <= (others=>'0');
      offset_o <= (others=>'0');

      wdptr <= '0';
      size <= (others=>'0');
      
      packetIndex <= 0;
      memoryWrite <= '0';
      memoryAddress <= (others=>'0');
      memoryDataIn <= (others=>'0');
    elsif (clk'event and clk = '1') then
      case state is
        when RECEIVE_PACKET =>
          ---------------------------------------------------------------------
          -- This state waits for a new maintenance packet, receives it
          -- and parses it.
          ---------------------------------------------------------------------
          if (inboundCyc_i = '1') then
            if (inboundAck = '0') then
              if (inboundStb_i = '1') then
                if (inboundAdr_i = x"80") then
                  -------------------------------------------------------------
                  -- Maintenance Read Request packet parser.
                  -------------------------------------------------------------
                  case (packetIndex) is
                    when 0 =>
                      -- x"0000" & ackid & vc & crf & prio & tt & ftype
                      vc_o <= inboundDat_i(9);
                      crf_o <= inboundDat_i(8);
                      prio_o <= inboundDat_i(7 downto 6);
                      tt_o <= inboundDat_i(5 downto 4);
                      packetIndex <= packetIndex + 1;
                    when 1 =>
                      -- dstid
                      dstid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 2 =>
                      -- srcid
                      srcid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 3 =>
                      -- transaction & rdsize & srcTID & hop & config_offset(20:13)
                      size <= inboundDat_i(27 downto 24);
                      tid_o <= inboundDat_i(23 downto 16);
                      hop_o <= inboundDat_i(15 downto 8);
                      offset_o(20 downto 13) <= inboundDat_i(7 downto 0);
                      packetIndex <= packetIndex + 1;
                    when 4 =>
                      -- config_offset(12:0) & wdptr & rsrv & crc(15:0)
                      offset_o(12 downto 0) <= inboundDat_i(31 downto 19);
                      wdptr <= inboundDat_i(18);
                      packetIndex <= packetIndex + 1;
                      readRequestComplete <= '1';
                    when others =>
                      -- There should be no more content in a maintenance read request.
                      -- Discard.
                      --report "Received unexpected packet content in read request." severity warning;
                  end case;
                  inboundAck <= '1';
                elsif (inboundAdr_i = x"81") then
                  -------------------------------------------------------------
                  -- Maintenance Write Request packet parser.
                  -------------------------------------------------------------
                  case (packetIndex) is
                    when 0 =>
                      -- x"0000" & ackid & vc & crf & prio & tt & ftype
                      vc_o <= inboundDat_i(9);
                      crf_o <= inboundDat_i(8);
                      prio_o <= inboundDat_i(7 downto 6);
                      tt_o <= inboundDat_i(5 downto 4);
                      packetIndex <= packetIndex + 1;
                    when 1 =>
                      -- destId
                      dstid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 2 =>
                      -- srcId
                      srcid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 3 =>
                      -- transaction & wrsize & srcTID & hop & config_offset(20:13)
                      size <= inboundDat_i(27 downto 24);
                      tid_o <= inboundDat_i(23 downto 16);
                      hop_o <= inboundDat_i(15 downto 8);
                      offset_o(20 downto 13) <= inboundDat_i(7 downto 0);
                      packetIndex <= packetIndex + 1;
                    when 4 =>
                      -- config_offset(12:0) & wdptr & rsrv & double-word(63:48)
                      offset_o(12 downto 0) <= inboundDat_i(31 downto 19);
                      wdptr <= inboundDat_i(18);
                      packetData(47 downto 32) <= inboundDat_i(15 downto 0);
                      packetIndex <= packetIndex + 1;
                    when 5 | 7 | 9 | 11 | 13 | 15 | 17 | 19 =>
                      -- double-word(47:16)
                      packetData(31 downto 0) <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 6 | 8 | 10 | 12 | 14 | 16 | 18 | 20 =>
                      -- double-word(15:0) & double-word(63:48)
                      packetData(47 downto 32) <= inboundDat_i(15 downto 0);
                      packetIndex <= packetIndex + 1;
                      memoryWrite <= '1';
                      memoryDataIn <= packetData & inboundDat_i(31 downto 16);
                      writeRequestComplete <= '1';
                    when others =>
                      -- There should be no more content in a maintenance write request.
                      -- Discard.
                      --report "Received unexpected packet content in write request." severity warning;
                  end case;
                  inboundAck <= '1';
                elsif (inboundAdr_i = x"82") then
                  -------------------------------------------------------------
                  -- Maintenance Read Response packet parser.
                  -------------------------------------------------------------
                  case (packetIndex) is
                    when 0 =>
                      -- x"0000" & ackid & vc & crf & prio & tt & ftype
                      vc_o <= inboundDat_i(9);
                      crf_o <= inboundDat_i(8);
                      prio_o <= inboundDat_i(7 downto 6);
                      tt_o <= inboundDat_i(5 downto 4);
                      packetIndex <= packetIndex + 1;
                    when 1 =>
                      -- destid
                      dstid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 2 =>
                      -- srcid
                      srcid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 3 =>
                      -- transaction & status & srcTID & hop & reserved(7:0)
                      status_o <= inboundDat_i(27 downto 24);
                      tid_o <= inboundDat_i(23 downto 16);
                      hop_o <= inboundDat_i(15 downto 8);
                      packetIndex <= packetIndex + 1;
                    when 4 =>
                      -- reserved(15:0) & wdptr & rsrv & double-word(63:48)
                      packetData(47 downto 32) <= inboundDat_i(15 downto 0);
                      packetIndex <= packetIndex + 1;
                    when 5 | 7 | 9 | 11 | 13 | 15 | 17 | 19 =>
                      -- double-word(47:16)
                      packetData(31 downto 0) <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 6 | 8 | 10 | 12 | 14 | 16 | 18 | 20 =>
                      -- double-word(15:0) & double-word(63:48)
                      packetData(47 downto 32) <= inboundDat_i(15 downto 0);
                      packetIndex <= packetIndex + 1;
                      memoryWrite <= '1';
                      memoryDataIn <= packetData & inboundDat_i(31 downto 16);
                      readResponseComplete <= '1';
                    when others =>
                      -- There should be no more content in a maintenance write request.
                      -- Discard.
                      --report "Received unexpected packet content in read response." severity warning;
                  end case;
                  inboundAck <= '1';
                elsif (inboundAdr_i = x"83") then
                  -------------------------------------------------------------
                  -- Maintenance Write Response packet parser.
                  -------------------------------------------------------------
                  case (packetIndex) is
                    when 0 =>
                      -- x"0000" & ackid & vc & crf & prio & tt & ftype
                      vc_o <= inboundDat_i(9);
                      crf_o <= inboundDat_i(8);
                      prio_o <= inboundDat_i(7 downto 6);
                      tt_o <= inboundDat_i(5 downto 4);
                      packetIndex <= packetIndex + 1;
                    when 1 =>
                      -- dstid
                      dstid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 2 =>
                      -- srcid
                      srcid_o <= inboundDat_i;
                      packetIndex <= packetIndex + 1;
                    when 3 =>
                      -- transaction & status & srcTID & hop & reserved(7:0)
                      status_o <= inboundDat_i(27 downto 24);
                      tid_o <= inboundDat_i(23 downto 16);
                      hop_o <= inboundDat_i(15 downto 8);
                      packetIndex <= packetIndex + 1;
                    when 4 =>
                      -- reserved(15:0) & crc(15:0)
                      packetIndex <= packetIndex + 1;
                      writeResponseComplete <= '1';
                    when others =>
                      -- There should be no more content in a maintenance read request.
                      -- Discard.
                      --report "Received unexpected packet content in write response." severity warning;
                  end case;
                  inboundAck <= '1';
                elsif (inboundAdr_i = x"84") then
                  -------------------------------------------------------------
                  -- Maintenance Port-Write Request packet parser.
                  -------------------------------------------------------------
                else
                  -------------------------------------------------------------
                  -- Unsupported maintenance packet.
                  -------------------------------------------------------------
                  -- Cannot handle these, dont answer.
                end if;
              end if;
            else
              if (memoryWrite = '1') then
                memoryAddress <= std_logic_vector(unsigned(memoryAddress) + 1);
              end if;
              
              memoryWrite <= '0';
              inboundAck <= '0';
            end if;
          else
            if ((readRequestComplete = '1') or (writeRequestComplete = '1') or
                (readResponseComplete = '1') or (writeResponseComplete = '1')) then
              state <= READY;
            else
              packetIndex <= 0;
              memoryAddress <= (others=>'0');
            end if;
          end if;

        when READY =>
          ---------------------------------------------------------------------
          -- Wait for the handler of the packet to signal that it has been
          -- processed.
          ---------------------------------------------------------------------
          if (done_i = '1') then
            packetIndex <= 0;
            memoryAddress <= (others=>'0');
            
            readRequestComplete <= '0';
            writeRequestComplete <= '0';
            readResponseComplete <= '0';
            writeResponseComplete <= '0';
            state <= RECEIVE_PACKET;
          end if;
          
        when others =>
          ---------------------------------------------------------------------
          -- 
          ---------------------------------------------------------------------

      end case;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Transformation of rdsize/wrsize into length of access and byte lanes.
  -----------------------------------------------------------------------------
  
  process(clk, areset_n)
  begin
    if (areset_n = '0') then
      size_o <= (others=>'0');
      wdptr_o <= '0';
      payloadLength_o <= (others=>'0');
    elsif (clk'event and clk = '1') then
      if (readRequestComplete = '1') or (writeRequestComplete = '1') then
        size_o <= size;
        wdptr_o <= wdptr;
        payloadLength_o <= memoryAddress;
      elsif (readResponseComplete = '1') then
        size_o <= size;
        wdptr_o <= wdptr;
        payloadLength_o <= memoryAddress;
      else
        size_o <= size;
        wdptr_o <= wdptr;
        payloadLength_o <= (others=>'0');
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Payload content memory.
  -----------------------------------------------------------------------------
  PayloadMemory: MemorySimpleDualPort
    generic map(ADDRESS_WIDTH=>3, DATA_WIDTH=>64)
    port map(clkA_i=>clk,
             enableA_i=>memoryWrite,
             addressA_i=>memoryAddress,
             dataA_i=>memoryDataIn,
             clkB_i=>clk,
             enableB_i=>enable,
             addressB_i=>payloadIndex_i,
             dataB_o=>payload_o);

end architecture;


-------------------------------------------------------------------------------
-- MaintenanceOutbound.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rio_common.all;

-------------------------------------------------------------------------------
-- Entity for MaintenanceOutbound.
-------------------------------------------------------------------------------
entity MaintenanceOutbound is
  port(
    clk : in std_logic;
    areset_n : in std_logic;
    enable : in std_logic;

    readRequestReady_i : in std_logic;
    writeRequestReady_i : in std_logic;
    readResponseReady_i : in std_logic;
    writeResponseReady_i : in std_logic;
    portWriteReady_i : in std_logic;
    vc_i : in std_logic;
    crf_i : in std_logic;
    prio_i : in std_logic_vector(1 downto 0);
    tt_i : in std_logic_vector(1 downto 0);
    dstid_i : in std_logic_vector(31 downto 0);
    srcid_i : in std_logic_vector(31 downto 0);
    size_i : in std_logic_vector(3 downto 0);
    status_i : in std_logic_vector(3 downto 0);
    tid_i : in std_logic_vector(7 downto 0);
    hop_i : in std_logic_vector(7 downto 0);
    offset_i : in std_logic_vector(20 downto 0);
    wdptr_i : in std_logic;
    payloadLength_i : in std_logic_vector(2 downto 0);
    payloadIndex_o : out std_logic_vector(2 downto 0);
    payload_i : in std_logic_vector(63 downto 0);
    done_o : out std_logic;
    
    outboundCyc_o : out std_logic;
    outboundStb_o : out std_logic;
    outboundDat_o : out std_logic_vector(31 downto 0);
    outboundAck_i : in std_logic);
end entity;


-------------------------------------------------------------------------------
-- Architecture for MaintenanceOutbound.
-------------------------------------------------------------------------------
architecture MaintenanceOutbound of MaintenanceOutbound is
  type StateType is (WAIT_PACKET,
                     READ_REQUEST, WRITE_REQUEST,
                     READ_RESPONSE, WRITE_RESPONSE,
                     WAIT_COMPLETE, RESPONSE_DONE);
  signal state : StateType;
  signal packetIndex : natural range 0 to 21;
  
  signal header : std_logic_vector(31 downto 0);
  signal payload : std_logic_vector(15 downto 0);
  signal payloadIndex : std_logic_vector(2 downto 0);
    
begin

  -- unused(31:16) | ackId(15:10) | vc(9) | crf(8) | prio(7:6) | tt(5:4) | ftype(3:0).
  header <= x"0000" & "000000" & vc_i & crf_i & prio_i & tt_i & x"8";

  payloadIndex_o <= payloadIndex;
  
  MaintenanceResponse: process(clk, areset_n)
  begin
    if (areset_n = '0') then
      state <= WAIT_PACKET;
      packetIndex <= 0;

      payload <= (others=>'0');
      payloadIndex <= (others=>'0');
      
      outboundCyc_o <= '0';
      outboundStb_o <= '0';

      done_o <= '0';
    elsif (clk'event and clk = '1') then
      if (enable = '1') then
        case state is
          when WAIT_PACKET =>
            -------------------------------------------------------------------
            -- 
            -------------------------------------------------------------------
            payloadIndex <= (others=>'0');
            if (readRequestReady_i = '1') then
              outboundCyc_o <= '1';
              outboundStb_o <= '1';
              outboundDat_o <= header;
              packetIndex <= 1;
              state <= READ_REQUEST;
            elsif (writeRequestReady_i = '1') then
              outboundCyc_o <= '1';
              outboundStb_o <= '1';
              outboundDat_o <= header;
              packetIndex <= 1;
              state <= WRITE_REQUEST;
            elsif (readResponseReady_i = '1') then
              outboundCyc_o <= '1';
              outboundStb_o <= '1';
              outboundDat_o <= header;
              packetIndex <= 1;
              state <= READ_RESPONSE;
            elsif (writeResponseReady_i = '1') then
              outboundCyc_o <= '1';
              outboundStb_o <= '1';
              outboundDat_o <= header;
              packetIndex <= 1;
              state <= WRITE_RESPONSE;
            end if;

          when READ_REQUEST =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            if (outboundAck_i = '1') then
              case (packetIndex) is
                when 1 =>
                  -- dstid
                  outboundDat_o <= dstid_i;
                  packetIndex <= packetIndex + 1;
                when 2 =>
                  -- srcid 
                  outboundDat_o <= srcid_i;
                  packetIndex <= packetIndex + 1;
                when 3 =>
                  -- transaction & rdsize & srcTID & hop & config_offset(20:13)
                  outboundDat_o <= "0000" & size_i & tid_i & hop_i & offset_i(20 downto 13);
                  packetIndex <= packetIndex + 1;
                when others =>
                  -- config_offset(12:0) & wdptr & rsrv & crc(15:0)
                  outboundDat_o <= offset_i(12 downto 0) & wdptr_i & "00" & x"0000";
                  packetIndex <= packetIndex + 1;
                  state <= WAIT_COMPLETE;
              end case;
            end if;

          when WRITE_REQUEST =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            if (outboundAck_i = '1') then
              case (packetIndex) is
                when 1 =>
                  -- dstid
                  outboundDat_o <= dstid_i;
                  packetIndex <= packetIndex + 1;
                when 2 =>
                  -- srcid 
                  outboundDat_o <= srcid_i;
                  packetIndex <= packetIndex + 1;
                when 3 =>
                  -- transaction & size & srcTID & hop & config_offset(20:13)
                  outboundDat_o <= "0001" & size_i & tid_i & hop_i & offset_i(20 downto 13);
                  packetIndex <= packetIndex + 1;
                when 4 =>
                  -- config_offset(12:0) & wdptr & rsrv & double-wordN(63:48)
                  outboundDat_o <= offset_i(12 downto 0) & wdptr_i & "00" & payload_i(63 downto 48);
                  packetIndex <= packetIndex + 1;
                when 5 | 7 | 9 | 11 | 13 | 15 | 17 | 19 =>
                  -- double-wordN(47:16)
                  outboundDat_o <= payload_i(47 downto 16);
                  payload <= payload_i(15 downto 0);
                  payloadIndex <= std_logic_vector(unsigned(payloadIndex) + 1);
                  packetIndex <= packetIndex + 1;
                when 6 | 8 | 10 | 12 | 14 | 16 | 18 =>
                  -- double-wordN(15:0) & double-wordN(63:48)
                  outboundDat_o <= payload & payload_i(63 downto 48);
                  packetIndex <= packetIndex + 1;
                  
                  if (payloadIndex = payloadLength_i) then
                    state <= WAIT_COMPLETE;
                  end if;
                when others =>
                  -- double-wordN(15:0) & double-wordN(63:48)
                  outboundDat_o <= payload & x"0000";
                  state <= WAIT_COMPLETE;
              end case;
            end if;
            
          when READ_RESPONSE =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            if (outboundAck_i = '1') then
              case (packetIndex) is
                when 1 =>
                  -- dstid
                  outboundDat_o <= dstid_i;
                  packetIndex <= packetIndex + 1;
                when 2 =>
                  -- srcid 
                  outboundDat_o <= srcid_i;
                  packetIndex <= packetIndex + 1;
                when 3 =>
                  -- transaction & status & targetTID & hop & reserved(7:0)
                  outboundDat_o <= "0010" & status_i & tid_i & hop_i & x"00";
                  packetIndex <= packetIndex + 1;
                when 4 =>
                  -- reserved(15:0) & double-wordN(63:48)
                  outboundDat_o <= x"0000" & payload_i(63 downto 48);
                  packetIndex <= packetIndex + 1;
                when 5 | 7 | 9 | 11 | 13 | 15 | 17 | 19 =>
                  -- double-wordN(47:16)
                  outboundDat_o <= payload_i(47 downto 16);
                  payload <= payload_i(15 downto 0);
                  payloadIndex <= std_logic_vector(unsigned(payloadIndex) + 1);
                  packetIndex <= packetIndex + 1;
                when 6 | 8 | 10 | 12 | 14 | 16 | 18 =>
                  -- double-wordN(15:0) & double-wordN(63:48)
                  outboundDat_o <= payload & payload_i(63 downto 48);
                  packetIndex <= packetIndex + 1;

                  if (payloadIndex = payloadLength_i) then
                    state <= WAIT_COMPLETE;
                  end if;
                when others =>
                  -- double-wordN(15:0) & double-wordN(63:48)
                  outboundDat_o <= payload & x"0000";
                  state <= WAIT_COMPLETE;
              end case;
            end if;
            
          when WRITE_RESPONSE =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            if (outboundAck_i = '1') then
              case (packetIndex) is
                when 1 =>
                  -- dstid
                  outboundDat_o <= dstid_i;
                  packetIndex <= packetIndex + 1;
                when 2 =>
                  -- srcid 
                  outboundDat_o <= srcid_i;
                  packetIndex <= packetIndex + 1;
                when 3 =>
                  -- transaction & status & targetTID & hop & reserved(7:0)
                  outboundDat_o <= "0011" & status_i & tid_i & hop_i & x"00";
                  packetIndex <= packetIndex + 1;
                when others =>
                  -- reserved(15:0) & crc(15:0)
                  outboundDat_o <= x"00000000";
                  packetIndex <= packetIndex + 1;
                  state <= WAIT_COMPLETE;
              end case;
            end if;

          when WAIT_COMPLETE =>
            -------------------------------------------------------------------
            -- 
            -------------------------------------------------------------------
            if (outboundAck_i = '1') then
              outboundCyc_o <= '0';
              outboundStb_o <= '0';
              state <= RESPONSE_DONE;
            end if;
            
          when RESPONSE_DONE =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            if ((readRequestReady_i = '0') and (writeRequestReady_i = '0') and
                (readResponseReady_i = '0') and (writeResponseReady_i = '0')) then
              state <= WAIT_PACKET;
              done_o <= '0';
            else
              done_o <= '1';
            end if;
            
          when others =>
            ---------------------------------------------------------------------
            -- 
            ---------------------------------------------------------------------
            state <= WAIT_PACKET;
            
        end case;
      end if;
    end if;
  end process;

end architecture;
