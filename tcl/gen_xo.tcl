# Package emitted Caelum RTL as a Vitis RTL kernel (.xo).
# vivado -mode batch -source gen_xo.tcl -tclargs <xo> <top> <kernel.xml> <rtl dir> <work dir>
#
# The top must follow the Vitis RTL kernel interface: ap_clk, ap_rst_n, an s_axi_control
# AXI4-Lite slave and one m_axi master per memory port, named like the ports in kernel.xml.
# Same flow as the Xilinx RTL kernel examples (package_kernel.tcl / gen_xo.tcl) blueVitis uses.

if { $::argc != 5 } {
    puts "usage: gen_xo.tcl <xo> <top> <kernel.xml> <rtl dir> <work dir>"
    exit 1
}
set xo   [lindex $::argv 0]
set top  [lindex $::argv 1]
set kxml [lindex $::argv 2]
set rtl  [lindex $::argv 3]
set work [lindex $::argv 4]

set packaged $work/ip
file delete -force $work
file mkdir $work

# kernel name and AXI ports come from kernel.xml
set fh [open $kxml r]
set xml [read $fh]
close $fh
if {![regexp {<kernel[^>]*name="([^"]+)"} $xml -> kname]} {
    puts "ERROR: no <kernel name=...> in $kxml"
    exit 1
}
set port_names {}
foreach {all name} [regexp -all -inline {<port name="([^"]+)"} $xml] {
    lappend port_names $name
}

create_project -force kernel_pack $work/project
# RTL reading is shared with caelum-target-vivado
source $::env(CAELUM_PROVIDER_VIVADO_DIR)/tcl/read_rtl.tcl
caelum_read_rtl $rtl project
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $packaged -vendor caelum.dev -library RTLKernel -taxonomy /KernelIP -import_files -set_current false
ipx::unload_core $packaged/component.xml
ipx::edit_ip_in_project -upgrade true -name kernel_edit -directory $packaged $packaged/component.xml

set core [ipx::current_core]
set_property core_revision 1 $core
foreach up [ipx::get_user_parameters] {
    ipx::remove_user_parameter [get_property NAME $up] $core
}
set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core
ipx::create_xgui_files $core
foreach p $port_names {
    ipx::associate_bus_interfaces -busif $p -clock ap_clk $core
}
set_property xpm_libraries {XPM_CDC XPM_MEMORY XPM_FIFO} $core
set_property supported_families { } $core
set_property auto_family_support_level level_2 $core
ipx::update_checksums $core
ipx::save_core $core
close_project -delete

if {[file exists $xo]} { file delete -force $xo }
package_xo -xo_path $xo -kernel_name $kname -ip_directory $packaged -kernel_xml $kxml
puts "wrote $xo"
