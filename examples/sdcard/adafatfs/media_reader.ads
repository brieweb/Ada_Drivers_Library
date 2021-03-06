------------------------------------------------------------------------------
--                        Bareboard drivers examples                        --
--                                                                          --
--                     Copyright (C) 2015-2016, AdaCore                     --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

package Media_Reader is

   type Media_Controller is limited interface;
   type Media_Controller_Access is access all Media_Controller'Class;

   type Block is array (Unsigned_16 range <>) of Unsigned_8;

   function Block_Size
     (Controller : in out Media_Controller) return Unsigned_32 is abstract;

   function Read_Block
     (Controller   : in out Media_Controller;
      Block_Number : Unsigned_32;
      Data         : out Block) return Boolean is abstract;

   function Write_Block
     (Controller   : in out Media_Controller;
      Block_Number : Unsigned_32;
      Data         : Block) return Boolean is abstract;

end Media_Reader;
