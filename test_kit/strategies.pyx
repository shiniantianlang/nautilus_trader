# -------------------------------------------------------------------------------------------------
# <copyright file="strategies.pyx" company="Nautech Systems Pty Ltd">
#  Copyright (C) 2015-2020 Nautech Systems Pty Ltd. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  https://nautechsystems.io
# </copyright>
# -------------------------------------------------------------------------------------------------

import numpy as np

from collections import deque
from datetime import timedelta
from typing import Deque

from nautilus_trader.model.events cimport Event
from nautilus_trader.model.identifiers cimport Symbol, Label, PositionId
from nautilus_trader.model.objects cimport Decimal, Price, Tick, BarSpecification, BarType, Bar, Instrument
from nautilus_trader.model.order cimport Order, AtomicOrder
from nautilus_trader.model.events cimport OrderRejected
from nautilus_trader.trade.strategy cimport TradingStrategy
from nautilus_trader.model.c_enums.currency cimport currency_from_string
from nautilus_trader.model.c_enums.security_type cimport SecurityType
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.c_enums.order_purpose cimport OrderPurpose
from nautilus_trader.model.c_enums.time_in_force cimport TimeInForce
from nautilus_trader.common.clock cimport Clock, TestClock
from nautilus_trader.trade.sizing cimport PositionSizer, FixedRiskSizer
from test_kit.mocks cimport ObjectStorer

from nautilus_indicators.atr cimport AverageTrueRange
from nautilus_indicators.average.ema cimport ExponentialMovingAverage


class PyStrategy(TradingStrategy):
    """
    A strategy which is empty and does nothing.
    """

    def __init__(self, bar_type: BarType):
        """
        Initializes a new instance of the PyStrategy class.
        """
        super().__init__(order_id_tag='001')
        self.bar_type = bar_type
        self.object_storer = ObjectStorer()

    def on_start(self):
        self.subscribe_bars(self.bar_type)

    def on_tick(self, tick):
        pass

    def on_bar(self, bar_type, bar):
        print(bar)
        self.object_storer.store_2(bar_type, bar)

    def on_instrument(self, instrument):
        pass

    def on_event(self, event):
        self.object_storer.store(event)

    def on_stop(self):
        pass

    def on_reset(self):
        pass

    def on_save(self):
        return {}

    def on_load(self, dict state):
        pass

    def on_dispose(self):
        pass


cdef class EmptyStrategy(TradingStrategy):
    """
    A strategy which is empty and does nothing.
    """

    def __init__(self, str order_id_tag):
        """
        Initializes a new instance of the EmptyStrategy class.

        :param order_id_tag: The order_id tag for the strategy (should be unique at trader level).
        """
        super().__init__(order_id_tag=order_id_tag)

    cpdef void on_start(self):
        pass

    cpdef void on_tick(self, Tick tick):
        pass

    cpdef void on_bar(self, BarType bar_type, Bar bar):
        pass

    cpdef void on_instrument(self, Instrument instrument):
        pass

    cpdef void on_event(self, Event event):
        pass

    cpdef void on_stop(self):
        pass

    cpdef void on_reset(self):
        pass

    cpdef dict on_save(self):
        return {}

    cpdef void on_load(self, dict state):
        pass

    cpdef void on_dispose(self):
        pass


cdef class TickTock(TradingStrategy):
    """
    A strategy to test correct sequencing of tick data and timers.
    """
    cdef readonly Instrument instrument
    cdef readonly BarType bar_type
    cdef readonly list store
    cdef readonly bint timer_running
    cdef readonly int time_alert_counter

    def __init__(self, Instrument instrument,  BarType bar_type,):
        """
        Initializes a new instance of the TickTock class.
        """
        super().__init__(order_id_tag='000')

        self.instrument = instrument
        self.bar_type = bar_type
        self.store = []
        self.timer_running = False
        self.time_alert_counter = 0

    cpdef void on_start(self):
        self.subscribe_bars(self.bar_type)
        self.subscribe_ticks(self.instrument.symbol)

    cpdef void on_tick(self, Tick tick):
        self.log.info(f'Received Tick({tick})')
        self.store.append(tick)

    cpdef void on_bar(self, BarType bar_type, Bar bar):
        self.log.info(f'Received {bar_type} Bar({bar})')
        self.store.append(bar)
        if not self.timer_running:
            self.clock.set_timer(label=Label(f'Test-Timer'),
                                 interval=timedelta(seconds=10))
            self.timer_running = True

        self.time_alert_counter += 1
        self.clock.set_time_alert(label=Label(f'Test-Alert-{self.time_alert_counter}'),
                            alert_time=bar.timestamp + timedelta(seconds=30))

    cpdef void on_instrument(self, Instrument instrument):
        pass

    cpdef void on_event(self, Event event):
        self.store.append(event)

    cpdef void on_stop(self):
        pass

    cpdef void on_reset(self):
        pass

    cpdef dict on_save(self):
        return {}

    cpdef void on_load(self, dict state):
        pass

    cpdef void on_dispose(self):
        pass


cdef class TestStrategy1(TradingStrategy):
    """"
    A simple strategy for unit testing.
    """
    cdef readonly ObjectStorer object_storer
    cdef readonly BarType bar_type
    cdef readonly ExponentialMovingAverage ema1
    cdef readonly ExponentialMovingAverage ema2
    cdef readonly PositionId position_id

    def __init__(self,
                 BarType bar_type,
                 str id_tag_strategy='001',
                 Clock clock=TestClock()):
        """
        Initializes a new instance of the TestStrategy1 class.
        """
        super().__init__(order_id_tag=id_tag_strategy, clock=clock)
        self.object_storer = ObjectStorer()
        self.bar_type = bar_type

        self.ema1 = ExponentialMovingAverage(10)
        self.ema2 = ExponentialMovingAverage(20)

        self.register_indicator(self.bar_type, self.ema1, self.ema1.update)
        self.register_indicator(self.bar_type, self.ema2, self.ema2.update)

        self.position_id = None

    cpdef void on_start(self):
        self.object_storer.store('custom start logic')
        self.account_inquiry()

    cpdef void on_tick(self, Tick tick):
        self.object_storer.store(tick)

    cpdef void on_bar(self, BarType bar_type, Bar bar):

        self.object_storer.store((bar_type, Bar))

        if bar_type == self.bar_type:
            if self.ema1.value > self.ema2.value:
                buy_order = self.order_factory.market(
                    self.bar_type.symbol,
                    Label('TestStrategy1_E'),
                    OrderSide.BUY,
                    100000)

                self.submit_order(buy_order, PositionId(str(buy_order.id)))
                self.position_id = buy_order.id

            elif self.ema1.value < self.ema2.value:
                sell_order = self.order_factory.market(
                    self.bar_type.symbol,
                    Label('TestStrategy1_E'),
                    OrderSide.SELL,
                    100000)

                self.submit_order(sell_order, PositionId(str(sell_order.id)))
                self.position_id = sell_order.id

    cpdef void on_instrument(self, Instrument instrument):
        self.object_storer.store(instrument)

    cpdef void on_event(self, Event event):
        self.object_storer.store(event)

    cpdef void on_stop(self):
        self.object_storer.store('custom stop logic')

    cpdef void on_reset(self):
        self.object_storer.store('custom reset logic')

    cpdef dict on_save(self):
        self.object_storer.store('custom save logic')
        return {}

    cpdef void on_load(self, dict state):
        self.object_storer.store('custom load logic')

    cpdef void on_dispose(self):
        self.object_storer.store('custom dispose logic')


cdef class EMACross(TradingStrategy):
    """"
    A simple moving average cross example strategy. When the fast EMA crosses
    the slow EMA then a STOP_MARKET atomic order is placed for that direction
    with a trailing stop and profit target at 1R risk.
    """
    cdef readonly Instrument instrument
    cdef readonly Symbol symbol
    cdef readonly BarType bar_type
    cdef readonly int precision
    cdef readonly double risk_bp
    cdef readonly double SL_atr_multiple
    cdef readonly double entry_buffer
    cdef readonly double SL_buffer
    cdef readonly object spreads
    cdef readonly ExponentialMovingAverage fast_ema
    cdef readonly ExponentialMovingAverage slow_ema
    cdef readonly AverageTrueRange atr
    cdef readonly PositionSizer position_sizer

    def __init__(self,
                 Instrument instrument,
                 BarSpecification bar_spec,
                 double risk_bp=10.0,
                 int fast_ema=10,
                 int slow_ema=20,
                 int atr_period=20,
                 double sl_atr_multiple=2.0,
                 str extra_id_tag=''):
        """
        Initializes a new instance of the EMACross class.

        :param bar_spec: The bar specification for the strategy.
        :param risk_bp: The risk per trade (basis points).
        :param fast_ema: The fast EMA period.
        :param slow_ema: The slow EMA period.
        :param atr_period: The ATR period.
        :param sl_atr_multiple: The ATR multiple for stop-loss prices.
        :param extra_id_tag: The extra tag to appends to the strategies identifier tag.
        """
        # Order id tag must be unique at trader level
        super().__init__(order_id_tag=instrument.symbol.code + extra_id_tag)

        # Custom strategy variables
        self.instrument = instrument
        self.symbol = instrument.symbol
        self.bar_type = BarType(instrument.symbol, bar_spec)
        self.precision = instrument.tick_precision

        self.risk_bp = risk_bp
        self.entry_buffer = instrument.tick_size.as_double()
        self.SL_atr_multiple = sl_atr_multiple
        self.SL_buffer = instrument.tick_size * 10.0

        # Track spreads for calculating average
        self.spreads = deque(maxlen=100)  # type: Deque[float]

        # Create the indicators for the strategy
        self.fast_ema = ExponentialMovingAverage(fast_ema)
        self.slow_ema = ExponentialMovingAverage(slow_ema)
        self.atr = AverageTrueRange(atr_period)

        # Register the indicators for updating
        self.register_indicator(self.bar_type, self.fast_ema, self.fast_ema.update)
        self.register_indicator(self.bar_type, self.slow_ema, self.slow_ema.update)
        self.register_indicator(self.bar_type, self.atr, self.atr.update)

        self.position_sizer = FixedRiskSizer(self.instrument)

    cpdef void on_start(self):
        """
        This method is called when self.start() is called, and after internal
        start logic.
        """
        # Put custom code to be run on strategy start here
        self.request_bars(self.bar_type)
        self.subscribe_instrument(self.symbol)
        self.subscribe_bars(self.bar_type)
        self.subscribe_ticks(self.symbol)

    cpdef void on_tick(self, Tick tick):
        """
        This method is called whenever a Tick is received by the strategy, and 
        after the Tick has been processed by the base class.
        The received Tick object is then passed into this method.

        :param tick: The received tick.
        """
        # self.log.info(f"Received Tick({tick})")  # For demonstration purposes
        self.spreads.append(float(tick.ask.as_double() - tick.bid.as_double()))

    cpdef void on_bar(self, BarType bar_type, Bar bar) except *:
        """
        This method is called whenever the strategy receives a Bar, and after the
        Bar has been processed by the base class.
        The received BarType and Bar objects are then passed into this method.

        :param bar_type: The received bar type.
        :param bar: The received bar.
        """
        # Check if indicators ready
        if not self.indicators_initialized():
            return  # Wait for indicators to warm up...

        # Check if tick data available
        if not self.has_ticks(self.symbol):
            return  # Wait for ticks...

        # Calculate average spread
        cdef double average_spread = np.mean(self.spreads)
        cdef double liquidity_ratio

        # Check market liquidity
        if average_spread == 0.0:
            return # Protect divide by zero
        else:
            liquidity_ratio = self.atr.value / average_spread
            if liquidity_ratio < 2.0:
                self.log.info(f"Liquidity Ratio == {liquidity_ratio} (no liquidity).")
                return

        cdef Price price_entry
        cdef Price price_stop_loss
        cdef Price price_take_profit
        cdef AtomicOrder atomic_order
        cdef double exchange_rate

        if self.count_orders_working() == 0 and self.is_flat():  # No active or pending positions
            # BUY LOGIC
            if self.fast_ema.value >= self.slow_ema.value:
                price_entry = Price(bar.high + self.entry_buffer + self.spreads[-1], self.precision)
                price_stop_loss = Price(bar.low - (self.atr.value * self.SL_atr_multiple), self.precision)
                price_take_profit = Price(price_entry + (price_entry.as_double() - price_stop_loss.as_double()), self.precision)

                if self.instrument.security_type == SecurityType.FOREX:
                    quote_currency = currency_from_string(self.instrument.symbol.code[3:])
                    exchange_rate = self.xrate_for_account(quote_currency)
                else:
                    exchange_rate = self.xrate_for_account(self.instrument.base_currency)

                position_size = self.position_sizer.calculate(
                    equity=self.account().free_equity,
                    risk_bp=self.risk_bp,
                    price_entry=price_entry,
                    price_stop_loss=price_stop_loss,
                    exchange_rate=exchange_rate,
                    commission_rate_bp=0.15,
                    hard_limit=0,
                    units=1,
                    unit_batch_size=1000)

                if position_size.value > 0:
                    atomic_order = self.order_factory.atomic_stop_market(
                        symbol=self.symbol,
                        order_side=OrderSide.BUY,
                        quantity=position_size,
                        price_entry=price_entry,
                        price_stop_loss=price_stop_loss,
                        price_take_profit=price_take_profit,
                        label=Label('S1'),
                        time_in_force=TimeInForce.GTD,
                        expire_time=bar.timestamp + timedelta(minutes=1))
                else:
                    atomic_order = None

            # SELL LOGIC
            elif self.fast_ema.value < self.slow_ema.value:
                price_entry = Price(bar.low - self.entry_buffer, self.precision)
                price_stop_loss = Price(bar.high + (self.atr.value * self.SL_atr_multiple) + self.spreads[-1], self.precision)
                price_take_profit = Price(price_entry - (price_stop_loss.as_double() - price_entry.as_double()), self.precision)

                if self.instrument.security_type == SecurityType.FOREX:
                    quote_currency = currency_from_string(self.instrument.symbol.code[3:])
                    exchange_rate = self.xrate_for_account(quote_currency)
                else:
                    exchange_rate = self.xrate_for_account(self.instrument.base_currency)

                position_size = self.position_sizer.calculate(
                    equity=self.account().free_equity,
                    risk_bp=self.risk_bp,
                    price_entry=price_entry,
                    price_stop_loss=price_stop_loss,
                    exchange_rate=exchange_rate,
                    commission_rate_bp=0.15,
                    hard_limit=0,
                    units=1,
                    unit_batch_size=1000)

                if position_size.value > 0:
                    atomic_order = self.order_factory.atomic_stop_market(
                        symbol=self.symbol,
                        order_side=OrderSide.SELL,
                        quantity=position_size,
                        price_entry=price_entry,
                        price_stop_loss=price_stop_loss,
                        price_take_profit=price_take_profit,
                        label=Label('S1'),
                        time_in_force=TimeInForce.GTD,
                        expire_time=bar.timestamp + timedelta(minutes=1))
                else:
                    atomic_order = None

            # ENTRY ORDER SUBMISSION
            if atomic_order:
                self.submit_atomic_order(atomic_order, self.position_id_generator.generate())

        # TRAILING STOP LOGIC
        cdef Order trailing_stop
        cdef Price temp_price
        for working_order in self.orders_working().values():
            if working_order.purpose == OrderPurpose.STOP_LOSS:
                # SELL SIDE ORDERS
                if working_order.is_sell:
                    temp_price = Price(bar.low - (self.atr.value * self.SL_atr_multiple), self.precision)
                    if temp_price > working_order.price:
                        self.modify_order(working_order, working_order.quantity, temp_price)
                # BUY SIDE ORDERS
                elif working_order.is_buy:
                    temp_price = Price(bar.high + (self.atr.value * self.SL_atr_multiple) + self.spreads[-1], self.precision)
                    if temp_price < working_order.price:
                        self.modify_order(working_order, working_order.quantity, temp_price)

    cpdef void on_instrument(self, Instrument instrument):
        """
        This method is called whenever the strategy receives an Instrument update.

        :param instrument: The received instrument.
        """
        if self.instrument.symbol.equals(instrument.symbol):
            self.instrument = instrument

        self.log.info(f"Updated instrument {instrument}.")

    cpdef void on_event(self, Event event):
        """
        This method is called whenever the strategy receives an Event object,
        after the event has been processed by the base class (updating any objects it needs to).
        These events could be AccountEvent, OrderEvent, PositionEvent, TimeEvent.

        :param event: The received event.
        """
        # Put custom code for event handling here (or pass)
        if isinstance(event, OrderRejected):
            position = self.position_for_order(event.order_id)
            if position is not None and position.is_open:
                self.flatten_position(position.id)

    cpdef void on_stop(self):
        """
        This method is called when self.stop() is called after internal
        stopping logic.
        """
        # Put custom code to be run on strategy stop here (or pass)
        pass

    cpdef void on_reset(self):
        """
        This method is called when self.reset() is called, and after internal
        reset logic such as clearing the internally held bars, ticks and resetting
        all indicators.
        """
        # Put custom code to be run on a strategy reset here (or pass)
        pass

    cpdef dict on_save(self):
        return {}

    cpdef void on_load(self, dict state):
        pass

    cpdef void on_dispose(self):
        """
        This method is called when self.dispose() is called. Dispose of any resources
        that had been used by the strategy here.
        """
        # Put custom code to be run on a strategy disposal here (or pass)
        self.unsubscribe_instrument(self.symbol)
        self.unsubscribe_bars(self.bar_type)
        self.unsubscribe_ticks(self.symbol)
