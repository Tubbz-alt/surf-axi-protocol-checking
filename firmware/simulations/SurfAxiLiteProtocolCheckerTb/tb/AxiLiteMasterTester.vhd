-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- This file is part of 'surf-axi-protocol-checking'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'surf-axi-protocol-checking', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.TextUtilPkg.all;

entity AxiLiteMasterTester is
   generic (
      TPD_G   : time    := 1 ns;
      INDEX_G : natural := 0);
   port (
      done             : out sl;
      failed           : out sl;
      -- AXI-Lite Register Interface (sysClk domain)
      axilClk          : in  sl;
      axilRst          : in  sl;
      mAxilReadMaster  : out AxiLiteReadMasterType;
      mAxilReadSlave   : in  AxiLiteReadSlaveType;
      mAxilWriteMaster : out AxiLiteWriteMasterType;
      mAxilWriteSlave  : in  AxiLiteWriteSlaveType);
end AxiLiteMasterTester;

architecture rtl of AxiLiteMasterTester is

   constant MAX_CNT_C : positive := 5;

   type StateType is (
      REQ_S,
      ACK_S,
      DONE_S);

   type RegType is record
      failed : sl;
      done   : sl;
      cnt    : slv(7 downto 0);
      req    : AxiLiteReqType;
      state  : StateType;
      data   : slv(31 downto 0);
   end record;

   constant REG_INIT_C : RegType := (
      failed => '0',
      done   => '0',
      cnt    => x"00",
      req    => AXI_LITE_REQ_INIT_C,
      state  => REQ_S,
      data   => (others => '0'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal ack : AxiLiteAckType;

begin

   U_AxiLiteMaster : entity surf.AxiLiteMaster
      generic map (
         TPD_G => TPD_G)
      port map (
         req             => r.req,
         ack             => ack,
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilWriteMaster => mAxilWriteMaster,
         axilWriteSlave  => mAxilWriteSlave,
         axilReadMaster  => mAxilReadMaster,
         axilReadSlave   => mAxilReadSlave);

   ---------------------
   -- AXI Lite Interface
   ---------------------
   comb : process (ack, axilRst, r) is
      variable v      : RegType;
      variable regCon : AxiLiteEndPointType;
   begin
      -- Latch the current value
      v := r;

      -- State Machine
      case (r.state) is
         ----------------------------------------------------------------------
         when REQ_S =>
            -- Check if ready for next transaction
            if (ack.done = '0') then

               -- Setup the AXI-Lite Master request
               v.req.request := '1';

               -- Setup the Address
               v.req.address(15 downto 2)  := resize(r.cnt, 14);
               v.req.address(31 downto 16) := toSlv(INDEX_G, 16);

               -- Setup the data
               v.req.wrData(15 downto 0)  := resize(r.cnt+1, 16);
               v.req.wrData(31 downto 16) := toSlv(INDEX_G, 16);

               -- Next state
               v.state := ACK_S;
            end if;
         ----------------------------------------------------------------------
         when ACK_S =>
            -- Wait for DONE to set
            if (ack.done = '1') then

               -- Reset the flag
               v.req.request := '0';

               -- Check for wrong read data
               if (r.req.rnw = '1') and (ack.rdData /= r.req.wrData) then
                  v.failed := '1';
               end if;

               -- Check for error response
               if (ack.resp /= 0) then
                  v.failed := '1';
               end if;

               -- Increment the counter
               v.cnt := r.cnt + 1;

               -- Check for max count
               if (r.cnt = x"FF") then

                  -- Check if write mode
                  if (r.req.rnw = '0') then

                     -- Switch to read mode
                     v.req.rnw := '1';

                     -- Next state
                     v.state := REQ_S;

                  else

                     -- Next state
                     v.state := DONE_S;

                  end if;

               else

                  -- Next state
                  v.state := REQ_S;

               end if;
            end if;
         ----------------------------------------------------------------------
         when DONE_S =>
            v.done := '1';
      ----------------------------------------------------------------------
      end case;

      -- Outputs
      done   <= r.done;
      failed <= r.failed;

      -- Reset
      if (axilRst = '1') then
         v         := REG_INIT_C;
         -- Default to write first
         v.req.rnw := '0';
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (axilClk) is
   begin
      if (rising_edge(axilClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
