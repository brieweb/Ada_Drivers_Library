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

with Ada.Unchecked_Conversion;
with FAT_Filesystem;             use FAT_Filesystem;

package body FAT_Filesystem.Files is

   ---------------
   -- File_Open --
   ---------------

   function File_Open
     (Parent : Directory_Entry;
      Name   : FAT_Name;
      Mode   : File_Mode;
      File   : out File_Handle) return Status_Code
   is
      Node : Directory_Entry;
      Ret  : Status_Code;
   begin
      Ret := Find (Parent, Name, Node);

      if Ret /= OK then
         if Mode = Read_Mode then
            return No_Such_File;
         end if;

         Ret := Create_File_Node (Parent, Name, Node);
      end if;

      if Ret /= OK then
         return Ret;
      end if;

      if Mode = Write_Mode then
         Set_Size (Node, 0);
         --  Free the cluster chain if > 1 cluster
         Ret := Adjust_Clusters (Node);

         if Ret /= OK then
            return Ret;
         end if;
      end if;

      File :=
        (Is_Open         => True,
         FS              => Get_FS (Node),
         Mode            => Mode,
         Current_Cluster => Get_Start_Cluster (Node),
         Current_Block   => 0,
         Buffer          => (others => 0),
         Buffer_Level    => 0,
         Bytes_Total     => 0,
         D_Entry         => Node,
         Parent          => Parent);

      return OK;
   end File_Open;

   ---------------
   -- File_Read --
   ---------------

   function File_Read
     (File : in out File_Handle;
      Data : out File_Data)
      return Integer
   is
      Idx         : Unsigned_16;
      --  Index from the current block

      Data_Length : Unsigned_16 := Data'Length;
      --  The total length to read

      Data_Idx    : Unsigned_16 := Data'First;
      --  Index into the data array of the next bytes to read

      N_Blocks    : Unsigned_32;
      --  The number of blocks to read at once

      Block_Addr  : Unsigned_32;
      --  The actual address of the block to read

      R_Length    : Unsigned_16;
      --  The size of the data to read in one operation

   begin
      if not File.Is_Open or File.Mode = Write_Mode then
         return -1;
      end if;

      --  Clamp the number of data to read to the size of the file
      if File.Bytes_Total + Data'Length > Get_Size (File.D_Entry) then
         Data_Length :=
           Unsigned_16 (Get_Size (File.D_Entry) - File.Bytes_Total);
      end if;

      --  Initialize the current cluster if not already done
      if File.Current_Cluster = 0 then
         File.Current_Cluster := Get_Start_Cluster (File.D_Entry);
      end if;

      loop
         Idx := Unsigned_16 (File.Bytes_Total mod File.FS.Block_Size_In_Bytes);
         Block_Addr := File.FS.Cluster_To_Block (File.Current_Cluster) +
           File.Current_Block;

         if Idx = 0
           and then Unsigned_32 (Data_Length) >= File.FS.Block_Size_In_Bytes
         then
            --  Case where the data to read is aligned on a block, and
            --  we have at least one block to read.

            --  Determine the number of full blocks we need to read:
            N_Blocks := Unsigned_32'Min
              (Unsigned_32 (File.FS.Number_Of_Blocks_Per_Cluster) -
                   File.Current_Block,
               Unsigned_32 (Data_Length) / File.FS.Block_Size_In_Bytes);

            --  Reading all blocks in one operation
            R_Length := Unsigned_16 (N_Blocks * File.FS.Block_Size_In_Bytes);

            --  Fill directly the user data
            if not File.FS.Controller.Read_Block
              (Block_Addr,
               Data (Data_Idx .. Data_Idx + R_Length - 1))
            then
               if Data_Idx = Data'First then
                  --  not a single byte read, report an error
                  return -1;
               else
                  return Integer (Data_Idx - Data'First);
               end if;
            end if;

            Data_Idx           := Data_Idx + R_Length;
            File.Current_Block := File.Current_Block + N_Blocks;
            File.Bytes_Total   := File.Bytes_Total + Unsigned_32 (R_Length);
            File.Buffer_Level  := 0;

         else
            --  Not aligned on a block, or less than 512 bytes to read
            --  We thus need to use our internal buffer.
            if File.Buffer_Level = 0 then
               Block_Addr := File.FS.Cluster_To_Block (File.Current_Cluster) +
                 File.Current_Block;
               if not File.FS.Controller.Read_Block
                 (Block_Addr,
                  File.Buffer)
               then
                  if Data_Idx = Data'First then
                     --  not a single byte read, report an error
                     return -1;
                  else
                     return Integer (Data_Idx - Data'First);
                  end if;
               end if;

               File.Buffer_Level := File.Buffer'Length;
            end if;

            R_Length :=
              Unsigned_16'Min (File.Buffer'Length - Idx, Data_Length);
            Data (Data_Idx .. Data_Idx + R_Length - 1) :=
              File.Buffer (Idx .. Idx + R_Length - 1);

            Data_Idx         := Data_Idx + R_Length;
            File.Bytes_Total := File.Bytes_Total + Unsigned_32 (R_Length);

            if Idx + R_Length = Unsigned_16 (File.FS.Block_Size_In_Bytes) then
               File.Current_Block := File.Current_Block + 1;
               File.Buffer_Level  := 0;
            end if;
         end if;

         --  Check if we changed cluster
         if File.Current_Block =
           Unsigned_32 (File.FS.Number_Of_Blocks_Per_Cluster)
         then
            File.Current_Cluster := File.FS.Get_FAT (File.Current_Cluster);
            File.Current_Block   := 0;
         end if;

         exit when Data_Idx - Data'First = Data_Length;
         exit when File.FS.Is_Last_Cluster (File.Current_Cluster);
      end loop;

      return Integer (Data_Idx - Data'First);
   end File_Read;

   ----------------
   -- File_Write --
   ----------------

   function File_Write
     (File   : in out File_Handle;
      Data   : File_Data) return Status_Code
   is
      procedure Inc_Size (Amount : Unsigned_16);

      Data_Length : Unsigned_16 := Data'Length;
      --  The total length to read

      Data_Idx    : Unsigned_16 := Data'First;
      --  Index into the data array of the next bytes to write

      N_Blocks    : Unsigned_32;
      --  The number of blocks to read at once

      Block_Addr  : Unsigned_32;
      --  The actual address of the block to read

      W_Length    : Unsigned_16;
      --  The size of the data to write in one operation

      --------------
      -- Inc_Size --
      --------------

      procedure Inc_Size (Amount : Unsigned_16)
      is
      begin
         Data_Idx := Data_Idx + Amount;
         File.Bytes_Total  := File.Bytes_Total + Unsigned_32 (Amount);
         Data_Length       := Data_Length - Amount;

         Set_Size (File.D_Entry, File.Bytes_Total);
      end Inc_Size;

   begin
      if not File.Is_Open or File.Mode = Read_Mode then
         return Access_Denied;
      end if;

      --  Initialize the current cluster if not already done
      if File.Current_Cluster = 0 then
         File.Current_Cluster := Get_Start_Cluster (File.D_Entry);
      end if;

      if File.Buffer_Level > 0 then
         --  First fill the buffer
         W_Length := Unsigned_16'Min (File.Buffer'Length - File.Buffer_Level,
                                  Data'Length);

         File.Buffer (File.Buffer_Level .. File.Buffer_Level + W_Length - 1) :=
           Data (Data_Idx .. Data_Idx + W_Length - 1);

         File.Buffer_Level := File.Buffer_Level + W_Length;
         Inc_Size (W_Length);

         if File.Buffer_Level > File.Buffer'Last then
            Block_Addr := File.FS.Cluster_To_Block (File.Current_Cluster) +
              File.Current_Block;

            File.Buffer_Level := 0;
            if not
              File.FS.Controller.Write_Block (Block_Addr, File.Buffer)
            then
               return Disk_Error;
            end if;

            File.Current_Block := File.Current_Block + 1;

            if File.Current_Block = Unsigned_32 (File.FS.Number_Of_Blocks_Per_Cluster) then
               File.Current_Block := 0;
               File.Current_Cluster := File.FS.Get_FAT (File.Current_Cluster);
            end if;
         end if;

         if Data_Idx > Data'Last then
            return OK;
         end if;
      end if;

      --  At this point, the buffer is empty and a new block is ready to be
      --  written. Check if we can write several blocks at once
      while Unsigned_32 (Data_Length) >= File.FS.Block_Size_In_Bytes loop
         --  we have at least one full block to write.

         --  Determine the number of full blocks we need to write:
         N_Blocks := Unsigned_32'Min
           (Unsigned_32 (File.FS.Number_Of_Blocks_Per_Cluster) -
                File.Current_Block,
            Unsigned_32 (Data_Length) / File.FS.Block_Size_In_Bytes);

         --  Writing all blocks in one operation
         W_Length := Unsigned_16 (N_Blocks * File.FS.Block_Size_In_Bytes);

         Block_Addr := File.FS.Cluster_To_Block (File.Current_Cluster) +
           File.Current_Block;

         --  Fill directly the user data
         if not File.FS.Controller.Write_Block
           (Block_Addr,
            Data (Data_Idx .. Data_Idx + W_Length - 1))
         then
            return Disk_Error;
         end if;

         Inc_Size (W_Length);

         if File.Current_Block = Unsigned_32 (File.FS.Number_Of_Blocks_Per_Cluster) then
            File.Current_Block := 0;
            File.Current_Cluster := File.FS.Get_FAT (File.Current_Cluster);
         end if;
      end loop;

      --  Now everything that remains is smaller than a block. Let's fill the
      --  buffer with this data
      W_Length := Data'Last - Data_Idx + 1;
      File.Buffer (0 .. W_Length - 1) := Data (Data_Idx .. Data'Last);

      Inc_Size (W_Length);

      File.Buffer_Level := W_Length;

      return OK;
   end File_Write;

   ----------------
   -- File_Flush --
   ----------------

   function File_Flush
     (File : in out File_Handle)
      return Status_Code
   is
      Block_Addr  : Unsigned_32;
      --  The actual address of the block to read
   begin
      if File.Mode = Read_Mode
        or else File.Buffer_Level = 0
      then
         return OK;
      end if;

      Block_Addr := File.FS.Cluster_To_Block (File.Current_Cluster) +
        File.Current_Block;

      if not File.FS.Controller.Write_Block (Block_Addr, File.Buffer) then
         return Disk_Error;
      end if;

      return OK;
   end File_Flush;

   ----------------
   -- File_Close --
   ----------------

   procedure File_Close (File : in out File_Handle) is
      Status : Status_Code with Unreferenced;
   begin
      Status := Update_Entry (File.Parent, File.D_Entry);
      Status := File_Flush (File);
      File.Is_Open := False;
   end File_Close;

   ------------------
   -- To_File_Data --
   ------------------

   function To_File_Data (S : String) return File_Data
   is
      subtype S_Type is String (S'Range);
      subtype D_Type is File_Data (0 .. S'Length - 1);
      function To_Data is new Ada.Unchecked_Conversion (S_Type, D_Type);
   begin
      return To_Data (S);
   end To_File_Data;

end FAT_Filesystem.Files;
