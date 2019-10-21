/////////////////////////////////////////////////////////////////////////////////////
// Copyright 2019 seabeam@yahoo.com - Licensed under the Apache License, Version 2.0
// For more information, see LICENCE in the main folder
/////////////////////////////////////////////////////////////////////////////////////
`ifndef YUU_AHB_MASTER_MONITOR_SV
`define YUU_AHB_MASTER_MONITOR_SV

class yuu_ahb_master_monitor extends uvm_monitor;
  virtual yuu_ahb_master_interface  vif;
  uvm_analysis_port #(yuu_ahb_item) out_monitor_ap;

  yuu_ahb_master_config cfg;
  uvm_event_pool events;
 
  semaphore m_cmd, m_data;

  protected yuu_ahb_item        monitor_item;
  protected yuu_ahb_addr_t      address_q[$];
  protected yuu_ahb_data_t      data_q[$];
  protected yuu_ahb_trans_e     trans_q[$];
  protected yuu_ahb_response_e  response_q[$];

  `uvm_register_cb(yuu_ahb_master_monitor, yuu_ahb_master_monitor_callback)

  `uvm_component_utils(yuu_ahb_master_monitor)

  extern                   function      new(string name, uvm_component parent);
  extern           virtual function void build_phase(uvm_phase phase);
  extern           virtual task          reset_phase(uvm_phase phase);
  extern           virtual task          main_phase(uvm_phase phase);

  extern protected virtual task          cmd_phase();
  extern protected virtual task          data_phase();
  extern protected virtual task          assembling_and_send(yuu_ahb_item monitor_item);
  extern protected virtual task          wait_reset(uvm_phase phase);
endclass

  function yuu_ahb_master_monitor::new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction 
  
  function void yuu_ahb_master_monitor::build_phase(uvm_phase phase);
    m_cmd = new(1);
    m_data = new(1);
    out_monitor_ap = new("out_monitor_ap", this);
  endfunction
  
  task yuu_ahb_master_monitor::reset_phase(uvm_phase phase);
    m_cmd.try_get();
    m_cmd.put();
    m_data.try_get();
    m_data.put();
    address_q.delete();
    data_q.delete();
    trans_q.delete();
    response_q.delete();
  endtask
  
  task yuu_ahb_master_monitor::main_phase(uvm_phase phase);
    wait(vif.hreset_n === 1'b1);
    @(vif.mon_cb);
    fork
      forever begin
        fork
          cmd_phase();
          data_phase();
        join_any
      end
      wait_reset(phase);
    join
  endtask
  

  task yuu_ahb_master_monitor::assembling_and_send(yuu_ahb_item monitor_item);
    int len = address_q.size()-1;
    yuu_ahb_item item = yuu_ahb_item::type_id::create("monitor_item"); 
    
    item.copy(monitor_item);
    item.len = len;
    item.address  = new[len+1];
    item.data     = new[len+1];
    item.trans    = new[len+1];
    item.response = new[len+1];

    item.location = new[len+1];

    for (int i=0; i<=len; i++) begin
      item.address[i] = address_q.pop_front();
      item.data[i]    = data_q.pop_front();
      item.trans[i]   = trans_q.pop_front();
      item.response[i]= response_q.pop_front();
    end

    foreach (item.location[i])
      item.location[i] = MIDDLE;
    item.location[0]  = FIRST;
    item.location[len]= LAST;

    item.start_address = item.address[0];
    
    item.end_time = $realtime();

    `uvm_do_callbacks(yuu_ahb_master_monitor, yuu_ahb_master_monitor_callback, post_collect(this, item));
    out_monitor_ap.write(item);
  endtask

  task yuu_ahb_master_monitor::cmd_phase();
    uvm_event monitor_cmd_begin = events.get($sformatf("%s_monitor_cmd_begin", cfg.get_name()));
    uvm_event monitor_cmd_end   = events.get($sformatf("%s_monitor_cmd_end", cfg.get_name()));

    m_cmd.get();
    while (vif.mon_cb.hready_i !== 1'b1)
      @vif.mon_cb;
    if (address_q.size()>0 && (vif.mon_cb.htrans == NONSEQ || vif.mon_cb.htrans == IDLE))
      assembling_and_send(monitor_item);

    while(vif.mon_cb.hready_i !== 1'b1 || (vif.mon_cb.htrans !== NONSEQ && vif.mon_cb.htrans !== IDLE)) begin
      if (vif.mon_cb.hready_i === 1'b1 && vif.mon_cb.htrans === SEQ) begin
        address_q.push_back(vif.mon_cb.haddr);
        trans_q.push_back(yuu_ahb_trans_e'(vif.mon_cb.htrans));
      end
      @vif.mon_cb;
    end

    monitor_cmd_begin.trigger();
    if (vif.mon_cb.htrans === NONSEQ) begin
      monitor_item = yuu_ahb_item::type_id::create("monitor_item");
      `uvm_do_callbacks(yuu_ahb_master_monitor, yuu_ahb_master_monitor_callback, pre_collect(this, monitor_item));

      monitor_item.direction  = yuu_ahb_direction_e'(vif.mon_cb.hwrite);
      monitor_item.size       = yuu_ahb_size_e'(vif.mon_cb.hsize);
      monitor_item.burst      = yuu_ahb_burst_e'(vif.mon_cb.hburst);
      monitor_item.prot3      = yuu_ahb_prot3_e'(vif.mon_cb.hprot[3]);
      monitor_item.prot2      = yuu_ahb_prot2_e'(vif.mon_cb.hprot[2]);
      monitor_item.prot1      = yuu_ahb_prot1_e'(vif.mon_cb.hprot[1]);
      monitor_item.prot0      = yuu_ahb_prot0_e'(vif.mon_cb.hprot[0]);
      monitor_item.prot6_emt  = yuu_ahb_emt_prot6_e'(vif.mon_cb.hprot_emt[6]);
      monitor_item.prot5_emt  = yuu_ahb_emt_prot5_e'(vif.mon_cb.hprot_emt[5]);
      monitor_item.prot4_emt  = yuu_ahb_emt_prot4_e'(vif.mon_cb.hprot_emt[4]);
      monitor_item.prot3_emt  = yuu_ahb_emt_prot3_e'(vif.mon_cb.hprot_emt[3]);
      monitor_item.master     = vif.mon_cb.hmaster  ;  
      monitor_item.lock       = vif.mon_cb.hmastlock;
      monitor_item.nonsec     = yuu_ahb_nonsec_e'(vif.mon_cb.hnonsec);
      
      monitor_item.burst_size = yuu_amba_size_e'(monitor_item.size);
      if (monitor_item.burst inside {WRAP4, WRAP8, WRAP16})
        monitor_item.burst_type = yuu_amba_pkg::WRAP;
      else
        monitor_item.burst_type = yuu_amba_pkg::INCR;
      monitor_item.address_aligned_enable = True;

      monitor_item.start_time = $realtime();
      address_q.push_back(vif.mon_cb.haddr);
      trans_q.push_back(yuu_ahb_trans_e'(vif.mon_cb.htrans));
    end

    @vif.mon_cb;
    monitor_cmd_end.trigger();

    m_cmd.put();
  endtask

  task yuu_ahb_master_monitor::data_phase();
    uvm_event monitor_data_begin = events.get($sformatf("%s_monitor_data_begin", cfg.get_name()));
    uvm_event monitor_data_end   = events.get($sformatf("%s_monitor_data_end", cfg.get_name()));
  
    m_data.get();
    while (vif.mon_cb.hready_i !== 1'b1 || (vif.mon_cb.htrans !== NONSEQ && vif.mon_cb.htrans !== SEQ))
      @vif.mon_cb;
    do
      @vif.mon_cb;
    while (vif.mon_cb.hready_i !== 1'b1);

    monitor_data_begin.trigger();

    if (monitor_item.direction == WRITE) begin
      data_q.push_back(vif.mon_cb.hwdata);
    end
    else if (monitor_item.direction == READ) begin
      data_q.push_back(vif.mon_cb.hrdata);
    end
    response_q.push_back(yuu_ahb_response_e'(vif.mon_cb.hresp));
  
    monitor_data_end.trigger();
    m_data.put();
  endtask

  task yuu_ahb_master_monitor::wait_reset(uvm_phase phase);
    @(negedge vif.hreset_n);
    phase.jump(uvm_reset_phase::get());
  endtask

`endif