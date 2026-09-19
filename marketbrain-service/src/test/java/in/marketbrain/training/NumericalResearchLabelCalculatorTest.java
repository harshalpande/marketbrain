package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static in.marketbrain.training.NumericalResearchLabelCalculator.Status.*;

class NumericalResearchLabelCalculatorTest {
    @Test void sharedOfflinePreflightArithmeticFixturesMatchJava() throws Exception {
        try(var input=getClass().getResourceAsStream("/numerical-label-parity.json")) {
            var fixtures=new com.fasterxml.jackson.databind.ObjectMapper().readTree(input);
            for(var fixture:fixtures.get("cases")) {
                var prices=bars();
                var entry=fixture.get("entry").decimalValue();var exit=fixture.get("exit").decimalValue();
                prices.put(calendar().get(1),new NumericalResearchLabelCalculator.Bar(calendar().get(1),entry,entry,entry,entry,true));
                prices.put(calendar().get(20),new NumericalResearchLabelCalculator.Bar(calendar().get(20),exit,exit,exit,exit,true));
                var result=calculator.calculate(decision,calendar(),prices,"SYNTHETIC","SYNTHETIC","TEST_SENSITIVITY",fixture.get("costBps").decimalValue());
                assertThat(result.grossReturnPercent()).isEqualByComparingTo(fixture.get("gross").decimalValue());
                assertThat(result.netReturnPercent()).isEqualByComparingTo(fixture.get("net").decimalValue());
                assertThat(result.trainingAuthorized()).isFalse();
            }
        }
    }
    final NumericalResearchLabelCalculator calculator=new NumericalResearchLabelCalculator();
    final LocalDate decision=LocalDate.of(2026,6,5);
    List<LocalDate> calendar() {
        // Synthetic explicit calendar, including non-weekday special sessions and gaps.
        List<LocalDate> dates=new ArrayList<>();dates.add(decision);
        for(int i=1;i<=20;i++){dates.add(decision.plusDays(i*2L));}
        return dates;
    }
    NumericalResearchLabelCalculator.Bar bar(LocalDate date,String open,String close,boolean executable) {
        return new NumericalResearchLabelCalculator.Bar(date,new BigDecimal(open),new BigDecimal("150"),
                new BigDecimal("50"),new BigDecimal(close),executable);
    }
    Map<LocalDate,NumericalResearchLabelCalculator.Bar> bars() {
        Map<LocalDate,NumericalResearchLabelCalculator.Bar> bars=new HashMap<>();
        calendar().forEach(date->bars.put(date,bar(date,"100","110",true)));return bars;
    }
    NumericalResearchLabelCalculator.Result run(List<LocalDate> dates,Map<LocalDate,NumericalResearchLabelCalculator.Bar> bars) {
        return calculator.calculate(decision,dates,bars,"SYNTHETIC_CALENDAR","SYNTHETIC_PRICES","TEST_COST",new BigDecimal("50"));
    }
    @Test void nextSessionOpenAndTwentiethSessionCloseWithExplicitCosts() {
        var result=run(calendar(),bars());
        assertThat(result.status()).isEqualTo(LABELED_RESEARCH_ONLY);
        assertThat(result.entryDate()).isEqualTo(calendar().get(1));
        assertThat(result.exitDate()).isEqualTo(calendar().get(20));
        assertThat(result.grossReturnPercent()).isEqualByComparingTo("10");
        assertThat(result.assumedCostPercent()).isEqualByComparingTo("0.5");
        assertThat(result.netReturnPercent()).isEqualByComparingTo("9.5");
        assertThat(result.trainingAuthorized()).isFalse();
    }
    @Test void absentEntryInteriorAndExitNeverShiftToAnotherAvailableBar() {
        for(int index:new int[]{1,8,20}) {
            var prices=bars();prices.remove(calendar().get(index));
            var result=run(calendar(),prices);
            assertThat(result.status()).isEqualTo(MISSING_BAR);
            assertThat(result.problemDate()).isEqualTo(calendar().get(index));
            assertThat(result.netReturnPercent()).isNull();
            assertThat(result.entryDate()).isEqualTo(calendar().get(1));
        }
    }
    @Test void incompleteCalendarCannotManufactureOutcome() {
        var result=run(calendar().subList(0,20),bars());
        assertThat(result.status()).isEqualTo(CALENDAR_HORIZON_UNAVAILABLE);
        assertThat(result.exitDate()).isNull();assertThat(result.grossReturnPercent()).isNull();
    }
    @Test void nonExecutableAndBadPricesAreNotLabels() {
        var prices=bars();var date=calendar().get(1);prices.put(date,bar(date,"100","110",false));
        assertThat(run(calendar(),prices).status()).isEqualTo(NON_EXECUTABLE_BAR);
        for(String value:new String[]{"0","-1","200"}) {
            prices.put(date,bar(date,value,"110",true));
            assertThat(run(calendar(),prices).status()).isEqualTo(INVALID_BAR);
        }
        prices.put(date,bar(date.plusDays(1),"100","110",true));
        assertThat(run(calendar(),prices).status()).isEqualTo(INVALID_BAR);
    }
    @Test void calendarAndPolicyInputsAreMandatory() {
        var duplicate=new ArrayList<>(calendar());duplicate.set(2,duplicate.get(1));
        assertThatThrownBy(()->run(duplicate,bars())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->run(calendar().subList(1,21),bars())).isInstanceOf(IllegalArgumentException.class);
        for(BigDecimal cost:Arrays.asList(null,new BigDecimal("-1"),new BigDecimal("10001"))) {
            assertThatThrownBy(()->calculator.calculate(decision,calendar(),bars(),"CAL","PRICE","COST",cost))
                    .isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(()->calculator.calculate(decision,calendar(),bars(),"","PRICE","COST",BigDecimal.ZERO))
                .isInstanceOf(IllegalArgumentException.class);
    }
    @Test void decisionCloseAndOutsideHorizonBarsCannotChangeLabel() {
        var prices=bars();var original=run(calendar(),prices);
        prices.put(decision,bar(decision,"80","90",true));
        prices.put(decision.plusDays(500),bar(decision.plusDays(500),"0","0",false));
        assertThat(run(calendar(),prices)).isEqualTo(original);
    }
    @Test void lossesAndFractionalCostsUseDecimalArithmetic() {
        var prices=bars();var exit=calendar().get(20);prices.put(exit,bar(exit,"100","90",true));
        var result=calculator.calculate(decision,calendar(),prices,"CAL","PRICE","COST",new BigDecimal("12.5"));
        assertThat(result.grossReturnPercent()).isEqualByComparingTo("-10");
        assertThat(result.netReturnPercent()).isEqualByComparingTo("-10.125");
    }
}
